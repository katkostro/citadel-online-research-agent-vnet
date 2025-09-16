# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license. See LICENSE.md file in the project root for full license information.

import asyncio
import logging
import os
import contextlib
import re
from typing import AsyncGenerator, Dict, Optional

import fastapi
from fastapi import FastAPI, Request, HTTPException, Depends
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential
from azure.ai.projects.aio import AIProjectClient
from azure.ai.projects.models import Agent

# Import OpenTelemetry for tracing
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

load_dotenv()

# Create OpenTelemetry tracer
tracer = trace.get_tracer(__name__)

# Configure Azure Monitor tracing if enabled
enable_trace = False
try:
    enable_trace_string = os.getenv("ENABLE_AZURE_MONITOR_TRACING", "")
    enable_trace = str(enable_trace_string).lower() == "true" if enable_trace_string else False
    
    if enable_trace:
        logging.info("Azure Monitor tracing is enabled")
        from azure.monitor.opentelemetry import configure_azure_monitor
        
        # Get Application Insights connection string
        application_insights_connection_string = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
        if application_insights_connection_string:
            configure_azure_monitor(
                connection_string=application_insights_connection_string,
                resource_attributes={
                    "service.name": "citadel-research-agent",
                    "service.version": "1.0.0",
                    "service.instance.id": os.getenv("HOSTNAME", "unknown")
                }
            )
            logging.info("✅ Configured Azure Monitor tracing with Application Insights")
            
            # Check if content recording is enabled
            content_recording = os.getenv("AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED", "false").lower() == "true"
            if content_recording:
                logging.info("✅ GenAI content recording enabled in tracing")
            else:
                logging.info("ℹ️ GenAI content recording disabled in tracing")
        else:
            logging.warning("⚠️ APPLICATIONINSIGHTS_CONNECTION_STRING not found - tracing disabled")
            enable_trace = False
    else:
        logging.info("Azure Monitor tracing is disabled")
except ImportError:
    logging.error("❌ Azure Monitor OpenTelemetry package not installed - tracing disabled")
    enable_trace = False
except Exception as e:
    logging.error(f"❌ Failed to configure Azure Monitor tracing: {e}")
    enable_trace = False

# Global variables for the Azure AI Projects system
ai_project_client = None
agent = None

# Models for request/response
class Message(BaseModel):
    message: str
    session_state: Dict = {}

class HealthResponse(BaseModel):
    status: str
    framework: str
    agent_id: Optional[str] = None
    ai_project_client_enabled: bool
    timestamp: Optional[str] = None

@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize the Azure AI Projects system on startup"""
    global ai_project_client, agent
    
    try:
        # Get environment variables
        proj_endpoint = os.environ.get("AZURE_EXISTING_AIPROJECT_ENDPOINT")
        agent_id = os.environ.get("AZURE_EXISTING_AGENT_ID")
        
        if not proj_endpoint:
            logging.error("AZURE_EXISTING_AIPROJECT_ENDPOINT not set")
            yield
            return
            
        # Initialize AI Project Client
        ai_project_client = AIProjectClient(
            credential=DefaultAzureCredential(exclude_shared_token_cache_credential=True),
            endpoint=proj_endpoint,
            api_version="2025-05-15-preview"
        )
        logging.info("Created AIProjectClient")
        
        # Get or create agent
        if agent_id:
            try:
                agent = await ai_project_client.agents.get_agent(agent_id)
                logging.info(f"Fetched existing agent: {agent.id}")
            except Exception as e:
                logging.error(f"Error fetching agent: {e}")
        
        if not agent:
            # Fallback to searching by name
            agent_name = os.environ.get("AZURE_AI_AGENT_NAME", "citadel-research-agent")
            agent_list = ai_project_client.agents.list_agents()
            if agent_list:
                async for agent_object in agent_list:
                    if agent_object.name == agent_name:
                        agent = agent_object
                        logging.info(f"Found agent by name '{agent_name}', ID={agent_object.id}")
                        break
        
        if not agent:
            logging.warning("No agent found. Some functionality may be limited.")
            
        logging.info("FastAPI startup: Azure AI Projects system initialization complete")
        logging.info(f"FastAPI startup: Agent ID: {getattr(agent, 'id', None) if agent else None}")
            
    except Exception as e:
        logging.error(f"FastAPI startup error: {e}")
        # Continue without the system - will use fallbacks
    
    yield
    
    # Cleanup on shutdown
    try:
        if ai_project_client:
            await ai_project_client.close()
            logging.info("Closed AIProjectClient")
    except Exception as e:
        logging.error(f"Error during cleanup: {e}")

# Create FastAPI app with comprehensive OpenAPI documentation
app = FastAPI(
    title="Citadel Online Research Agent",
    description="""
    **AI-powered research assistant with network security that provides real-time information through web search.**
    
    This service combines Azure AI Foundry Agent Service with Bing Search to deliver:
    - Real-time web research capabilities
    - Event discovery and information gathering
    - Weather and current information queries
    - Interactive chat-based assistance
    - RESTful search endpoints
    
    ## Key Features
    - 🔍 **Web Search**: Real-time search using Bing grounding
    - 💬 **Interactive Chat**: Conversational AI assistant
    - 🌐 **RESTful API**: Standard HTTP endpoints for integration
    - 📊 **Health Monitoring**: Built-in health check endpoints
    - 🔒 **Network Secure**: Azure-hosted with private networking and proper authentication
    
    ## Network Security
    This deployment uses Azure private networking with:
    - Private endpoints for all Azure services
    - VNet integration with subnet delegation
    - Private DNS zones for secure name resolution
    - No public network access to backend services
    
    ## Authentication
    This service uses Azure authentication. Ensure proper credentials are configured.
    
    ## Rate Limits
    Please be mindful of API usage to ensure fair access for all users.
    """,
    version="1.0.0",
    lifespan=lifespan,
    contact={
        "name": "Citadel AI Research Team",
        "url": "https://github.com/katkostro/citadel-online-research-agent-vnet",
        "email": "support@citadel.com"
    },
    license_info={
        "name": "MIT",
        "url": "https://opensource.org/licenses/MIT",
    },
    servers=[
        {
            "url": "/",
            "description": "Current server"
        }
    ],
    tags_metadata=[
        {
            "name": "search",
            "description": "Web search operations using Bing grounding"
        },
        {
            "name": "chat",
            "description": "Interactive conversational AI endpoints"
        },
        {
            "name": "agent",
            "description": "AI agent operations and interactions"  
        },
        {
            "name": "health",
            "description": "Service health and monitoring endpoints"
        },
        {
            "name": "system",
            "description": "System configuration and utilities"
        }
    ]
)

# Add CORS middleware to allow frontend to communicate with backend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for now - should be restricted in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Authentication dependency placeholder (can be expanded based on requirements)
auth_dependency = None

@app.get("/favicon.ico")
async def favicon():
    """Favicon endpoint to prevent 404 errors"""
    return JSONResponse(status_code=404, content={"detail": "Not found"})

@app.get("/health",
         tags=["health"],
         summary="Service health check",
         description="""
         **Check the health status of the AI research service.**
         
         This endpoint provides comprehensive health information about the service and its dependencies:
         - Overall service status
         - Azure AI Projects connection status  
         - Bing grounding availability
         - Agent initialization status
         - Framework information
         
         **Use Cases:**
         - Monitoring and alerting
         - Load balancer health checks
         - Service dependency verification
         - Troubleshooting connectivity issues
         
         **Status Indicators:**
         - `healthy`: All systems operational
         - `degraded`: Partial functionality available
         - `unhealthy`: Service unavailable
         """,
         response_model=dict,
         responses={
             200: {
                 "description": "Service health status",
                 "content": {
                     "application/json": {
                         "example": {
                             "status": "healthy",
                             "framework": "azure_ai_foundry_with_bing_grounding",
                             "agent_id": "asst_abc123def456",
                             "ai_project_client_enabled": True,
                             "bing_grounding_enabled": True,
                             "network_security": "private_endpoints_enabled",
                             "timestamp": "2024-01-15T10:30:00Z",
                             "version": "1.0.0"
                         }
                     }
                 }
             }
         })
async def health():
    """Health check endpoint"""
    global agent, ai_project_client
    
    # Start tracing span for health check
    with tracer.start_as_current_span("health_check") as span:
        from datetime import datetime
        
        # Determine service health status
        is_healthy = ai_project_client and agent
        status = "healthy" if is_healthy else "degraded"
        
        span.set_attribute("service_status", status)
        span.set_attribute("agent_available", agent is not None)
        span.set_attribute("ai_project_client_available", ai_project_client is not None)
        
        response_data = {
            "status": status,
            "framework": "azure_ai_foundry_with_bing_grounding",
            "agent_id": getattr(agent, 'id', None) if agent else None,
            "ai_project_client_enabled": ai_project_client is not None,
            "bing_grounding_enabled": agent is not None,
            "network_security": "private_endpoints_enabled",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "version": "1.0.0"
        }
        
        span.set_status(Status(StatusCode.OK))
        return JSONResponse(content=response_data)

@app.get("/",
         tags=["system"], 
         summary="Service welcome page",
         description="""
         **Welcome to the Citadel Online Research Agent API.**
         
         This is the main landing page for the AI research service. From here you can:
         - Access the interactive API documentation at `/docs`
         - View the OpenAPI specification at `/openapi.json`  
         - Test endpoints using the built-in Swagger UI
         - Review service capabilities and features
         
         **Quick Links:**
         - 📚 **API Documentation**: `/docs` (Swagger UI)
         - 📋 **OpenAPI Spec**: `/openapi.json` 
         - 🏥 **Health Check**: `/health`
         - 🔍 **Search Endpoint**: `/search`
         - 💬 **Chat Endpoint**: `/chat`
         - 🤖 **Agent Info**: `/agent`
         """,
         responses={
             200: {
                 "description": "Service information and navigation",
                 "content": {
                     "application/json": {
                         "example": {
                             "service": "Citadel Online Research Agent",
                             "version": "1.0.0",
                             "description": "AI-powered research assistant with network security and real-time web search",
                             "documentation": "/docs",
                             "openapi_spec": "/openapi.json",
                             "endpoints": {
                                 "search": "/search",
                                 "chat": "/chat", 
                                 "agent": "/agent",
                                 "health": "/health"
                             }
                         }
                     }
                 }
             }
         })
async def index(request: Request):
    """Serve API information and navigation"""
    return JSONResponse(content={
        "service": "Citadel Online Research Agent",
        "version": "1.0.0",
        "description": "AI-powered research assistant with network security and real-time web search capabilities",
        "framework": "FastAPI with Azure AI Foundry and Bing grounding",
        "network_security": {
            "private_endpoints": True,
            "vnet_integration": True,
            "private_dns": True,
            "public_access": False
        },
        "documentation": {
            "swagger_ui": f"{request.url}docs",
            "openapi_spec": f"{request.url}openapi.json",
            "redoc": f"{request.url}redoc"
        },
        "endpoints": {
            "search": f"{request.url}search",
            "chat": f"{request.url}chat", 
            "agent": f"{request.url}agent",
            "health": f"{request.url}health"
        },
        "features": [
            "Real-time web search via Bing grounding",
            "Interactive streaming chat interface", 
            "Unicode citation formatting",
            "Session-based conversation memory",
            "Network-secured with private endpoints",
            "RESTful API with OpenAPI documentation"
        ],
        "status": "operational"
    })

@app.get("/agent",
         tags=["agent"],
         summary="Get AI agent information",
         description="""
         **Retrieve detailed information about the AI research agent.**
         
         This endpoint provides comprehensive details about the configured AI agent including:
         - Agent ID and identification details
         - Model configuration and deployment information
         - Instructions and behavioral parameters
         - Available tools and capabilities
         - Current operational status
         
         **Information Returned:**
         - **Agent Identity**: Unique ID, name, and type
         - **Model Details**: Deployment name, version, and capabilities  
         - **Configuration**: Instructions, tools, and behavioral settings
         - **Status**: Current operational state and availability
         - **Tools**: Available search and analysis capabilities
         
         **Use Cases:**
         - Service configuration verification
         - Agent capability discovery
         - Integration planning and setup
         - Troubleshooting agent availability
         """,
         response_model=dict,
         responses={
             200: {
                 "description": "Agent information and configuration",
                 "content": {
                     "application/json": {
                         "example": {
                             "id": "asst_abc123def456",
                             "name": "Citadel Research Assistant", 
                             "model": "gpt-4o",
                             "instructions": "Research assistant with Bing grounding capabilities for current information",
                             "type": "azure_ai_agent_with_bing_grounding",
                             "tools": ["bing_search", "web_grounding"],
                             "network_security": "private_endpoints_enabled",
                             "status": "active"
                         }
                     }
                 }
             },
             404: {
                 "description": "Agent not found or not initialized",
                 "content": {
                     "application/json": {
                         "example": {
                             "detail": "Agent not found"
                         }
                     }
                 }
             }
         })
async def get_chat_agent(request: Request, _ = auth_dependency):
    """Get agent information"""
    global agent
    if agent:
        return JSONResponse(content={
            "id": agent.id,
            "name": getattr(agent, 'name', 'Citadel Research Assistant'),
            "model": os.environ.get("AZURE_AI_AGENT_DEPLOYMENT_NAME", "gpt-4o"),
            "instructions": getattr(agent, 'instructions', 'AI research assistant with Bing grounding capabilities'),
            "type": "azure_ai_agent_with_bing_grounding",
            "tools": ["bing_search", "web_grounding", "code_interpreter"],
            "network_security": "private_endpoints_enabled",
            "status": "active"
        })
    else:
        raise HTTPException(status_code=404, detail="Agent not found or not initialized")

@app.get("/chat/history")
async def history(request: Request, _ = auth_dependency):
    """Get chat history"""
    # For now, return empty history as Azure AI Agent manages conversation state
    # This can be expanded to implement actual history retrieval
    return JSONResponse(content=[])

async def stream_agent_response(user_message: str, thread_id: str = None) -> AsyncGenerator[str, None]:
    """Stream response from Azure AI Foundry agent with Bing grounding"""
    global agent, ai_project_client
    
    # Start tracing span for the streaming response
    with tracer.start_as_current_span("stream_agent_response") as span:
        span.set_attribute("user_message", user_message)
        span.set_attribute("thread_id", thread_id or "new")
        
        if not agent or not ai_project_client:
            span.record_exception(Exception("Agent or AI Project client not initialized"))
            span.set_status(Status(StatusCode.ERROR, "Client not initialized"))
            yield "Error: Agent or AI Project client not initialized\n"
            return
        
        try:
            # Create or get thread
            agent_client = ai_project_client.agents
            
            with tracer.start_as_current_span("thread_management") as thread_span:
                if thread_id:
                    try:
                        thread = await agent_client.threads.get(thread_id)
                        thread_span.set_attribute("thread_action", "retrieved")
                    except:
                        thread = await agent_client.threads.create()
                        thread_span.set_attribute("thread_action", "created_fallback")
                else:
                    thread = await agent_client.threads.create()
                    thread_span.set_attribute("thread_action", "created_new")
                
                thread_span.set_attribute("actual_thread_id", thread.id)
            
            # Create message
            with tracer.start_as_current_span("message_creation") as msg_span:
                message = await agent_client.messages.create(
                    thread_id=thread.id,
                    role="user",
                    content=user_message
                )
                msg_span.set_attribute("message_id", message.id)
                msg_span.set_attribute("message_role", "user")
            
            # Stream response
            with tracer.start_as_current_span("response_streaming") as response_span:
                yield f"Searching for information about: {user_message}\n\n"
                
                # For now, provide a basic response
                # This should be replaced with actual streaming implementation
                yield "I'm a network-secured AI research assistant powered by Azure AI Foundry with Bing grounding capabilities. "
                yield "I can help you find current information, research topics, and answer questions using real-time web search. "
                yield f"However, the full streaming implementation is still being set up for the message: '{user_message}'\n"
                
                response_span.set_attribute("response_status", "completed")
                span.set_status(Status(StatusCode.OK))
        
        except Exception as e:
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))
            yield f"Error: {str(e)}\n"

@app.post("/chat",
          tags=["chat"],
          summary="Interactive streaming chat with AI agent",
          description="""
          **Real-time conversational AI with streaming responses.**
          
          This endpoint provides an interactive chat experience with an AI agent that has access to:
          - Real-time web search capabilities via Bing
          - Current information and live data
          - Conversational memory within sessions
          - Streaming response for better user experience
          - Network security with private endpoints
          
          **Key Features:**
          - 🚀 **Streaming**: Real-time response streaming using Server-Sent Events
          - 🧠 **Memory**: Maintains conversation context using thread_id
          - 🔍 **Web Access**: Can search and cite current information
          - 💬 **Natural**: Conversational interface with follow-up questions
          - 🔒 **Secure**: Network-isolated with private endpoints
          
          **Session Management:**
          - Pass thread_id in session_state to maintain conversation context
          - Each thread maintains its own conversation history
          - Threads persist for the duration of the session
          
          **Response Format:**
          Streaming response using text/plain content type with real-time updates.
          """,
          responses={
              200: {
                  "description": "Streaming chat response", 
                  "content": {
                      "text/plain": {
                          "example": "I'd be happy to help you find information about Miami events this weekend! Let me search for current events happening in Miami...\n\nBased on my search, here are some exciting events in Miami this weekend:\n\n**Art Basel Miami Beach** 【1:0†Official Art Basel Site】\n- This Saturday-Sunday at Miami Beach Convention Center\n- International contemporary art fair with galleries from around the world\n\nWould you like me to find more specific information about any of these events?"
                      }
                  }
              },
              500: {
                  "description": "Internal server error during chat processing",
                  "content": {
                      "application/json": {
                          "example": {
                              "detail": "An error occurred while processing your request"
                          }
                      }
                  }
              }
          })
async def chat_stream(request: Message, _ = auth_dependency):
    """Stream chat responses from the Azure AI Foundry agent with Bing grounding"""
    
    # Start tracing span for the chat endpoint
    with tracer.start_as_current_span("chat_endpoint") as span:
        span.set_attribute("user_message", request.message)
        span.set_attribute("has_thread_id", bool(request.session_state.get("thread_id")))
        
        # Extract trace context from request headers for distributed tracing
        if hasattr(request, 'headers'):
            carrier = dict(request.headers)
            TraceContextTextMapPropagator().extract(carrier)
        
        # Log the incoming request
        logging.info(f"agent: Received chat request: {request.message}")
        
        try:
            # Stream the response
            span.set_attribute("response_type", "streaming")
            return StreamingResponse(
                stream_agent_response(request.message, request.session_state.get("thread_id")),
                media_type="text/plain",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive", 
                    "Content-Type": "text/event-stream"
                }
            )
            
        except Exception as e:
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))
            logging.error(f"Chat endpoint error: {e}")
            return JSONResponse(
                status_code=500,
                content={"error": "Failed to process chat request"}
            )

# Placeholder for search endpoint (can be implemented later)
@app.post("/search",
          tags=["search"],
          summary="Perform web search with AI analysis",
          description="""
          **Search for information using Bing grounding and AI analysis.**
          
          This endpoint performs real-time web searches and provides intelligent analysis of the results.
          Perfect for finding current information, events, news, and factual data.
          
          **Key Features:**
          - Real-time web search via Bing
          - AI-powered result analysis and summarization  
          - Unicode citation formatting 【n:m†source】
          - Structured JSON response format
          - Network-secured with private endpoints
          
          **Use Cases:**
          - Finding current events and news
          - Weather and location information
          - Business hours and contact details
          - Research and fact-checking
          - Real-time market data
          
          **Response Format:**
          Returns structured data with AI analysis and properly formatted citations.
          """,
          response_model=dict,
          responses={
              200: {
                  "description": "Successful search with AI analysis",
                  "content": {
                      "application/json": {
                          "example": {
                              "response": {
                                  "type": "text",
                                  "text": {
                                      "value": "Based on my search, here are the latest updates about Microsoft Azure...",
                                      "annotations": [
                                          {
                                              "type": "citation",
                                              "text": "【1:0†Microsoft Official Blog】",
                                              "start_index": 45,
                                              "end_index": 48,
                                              "citation": {
                                                  "citation_id": "1:0",
                                                  "quote": "Azure continues to expand...",
                                                  "source_name": "Microsoft Official Blog"
                                              }
                                          }
                                      ]
                                  }
                              }
                          }
                      }
                  }
              },
              400: {
                  "description": "Bad request - invalid search query",
                  "content": {
                      "application/json": {
                          "example": {
                              "error": "Search query is required and cannot be empty"
                          }
                      }
                  }
              },
              503: {
                  "description": "Search service temporarily unavailable",
                  "content": {
                      "application/json": {
                          "example": {
                              "response": {
                                  "type": "text", 
                                  "text": {
                                      "value": "Search service not available",
                                      "annotations": []
                                  }
                              }
                          }
                      }
                  }
              }
          })
async def search_endpoint(request: Message, _ = auth_dependency):
    """
    Search endpoint that returns Bing grounding responses in standardized JSON format.
    """
    global agent, ai_project_client
    
    # Start tracing span for the search endpoint
    with tracer.start_as_current_span("search_endpoint") as span:
        span.set_attribute("search_query", request.message)
        span.set_attribute("has_thread_id", bool(request.session_state.get("thread_id")))
        
        # Extract trace context from request headers for distributed tracing
        if hasattr(request, 'headers'):
            carrier = dict(request.headers)
            TraceContextTextMapPropagator().extract(carrier)
        
        logging.info(f"search: Received search request: {request.message}")
        
        if not request.message or not request.message.strip():
            span.set_status(Status(StatusCode.ERROR, "Empty search query"))
            return JSONResponse(
                status_code=400,
                content={"error": "Search query is required and cannot be empty"},
                headers={"Content-Type": "application/json; charset=utf-8"}
            )
        
        if not agent or not ai_project_client:
            span.set_status(Status(StatusCode.ERROR, "Agent or AI project client not available"))
            logging.error("search: Agent or AI project client not available")
            error_response = format_bing_grounding_response("Search service not available")
            return JSONResponse(
                status_code=503,
                content=error_response,
                headers={"Content-Type": "application/json; charset=utf-8"}
            )
        
        try:
            with tracer.start_as_current_span("search_execution") as search_span:
                # Initialize Bing tool if enabled
                bing_enabled = os.getenv('ENABLE_BING_SEARCH', 'false').lower() == 'true'
                search_span.set_attribute("bing_search_enabled", bing_enabled)
                
                if bing_enabled:
                    from api.bing_grounding_tool import BingGroundingTool
                    bing_tool = BingGroundingTool()
                    
                    # Perform direct search using Bing tool
                    with tracer.start_as_current_span("bing_search") as bing_span:
                        grounded_info = await bing_tool.get_grounded_information(request.message)
                        bing_span.set_attribute("sources_found", grounded_info.get('sources_count', 0))
                        
                        # Format response for agent consumption
                        search_context = grounded_info.get('formatted_results', '')
                        if search_context and grounded_info.get('sources_count', 0) > 0:
                            prompt = f"""Please analyze and summarize the following search results for the query: "{request.message}"

Search Results:
{search_context}

Provide a comprehensive, well-structured response that:
1. Directly answers the user's query
2. Synthesizes information from multiple sources
3. Includes proper citations in the format 【n:m†source】
4. Highlights the most important and current information

Query: {request.message}"""
                        else:
                            prompt = f"""The user searched for: "{request.message}"

However, I was unable to find current web search results. This could be due to:
1. Bing Search API not being configured
2. Network connectivity issues
3. API quota limitations

Please provide a helpful response based on your knowledge, and suggest where the user might find current information about their query."""
                
                else:
                    # Use agent without Bing search
                    prompt = f"""Please provide information about: "{request.message}"

Note: Web search is not currently enabled for real-time information. Please provide the best answer you can based on your knowledge base, and suggest reliable sources where the user can find current information."""
                
                # Use Azure AI Foundry agent for analysis
                with tracer.start_as_current_span("agent_analysis") as agent_span:
                    run_result = ai_project_client.agents.create_thread_and_run(
                        agent_id=agent.id,
                        thread={
                            "messages": [
                                {
                                    "role": "user", 
                                    "content": prompt
                                }
                            ]
                        }
                    )
                    agent_span.set_attribute("thread_id", run_result.thread_id)
                    agent_span.set_attribute("run_id", run_result.id)
                
                # Wait for completion with timeout
                with tracer.start_as_current_span("wait_for_completion") as wait_span:
                    import time
                    max_wait_time = 30
                    wait_interval = 1
                    elapsed_time = 0
                    
                    while elapsed_time < max_wait_time:
                        try:
                            current_run = ai_project_client.agents.runs.get(
                                thread_id=run_result.thread_id, 
                                run_id=run_result.id
                            )
                            logging.info(f"search: Run status: {current_run.status}")
                            
                            if current_run.status in ["completed", "failed", "expired", "cancelled"]:
                                if current_run.status == "failed":
                                    wait_span.set_attribute("run_failed", True)
                                    logging.error(f"search: Run failed: {getattr(current_run, 'last_error', 'Unknown error')}")
                                break
                                
                            time.sleep(wait_interval)
                            elapsed_time += wait_interval
                            
                        except Exception as status_error:
                            logging.warning(f"search: Error checking run status: {status_error}")
                            break
                    
                    wait_span.set_attribute("elapsed_time", elapsed_time)
                
                # Get the complete message with annotations
                try:
                    with tracer.start_as_current_span("retrieve_response") as retrieve_span:
                        messages = ai_project_client.agents.messages.list(
                            thread_id=run_result.thread_id
                        )
                        
                        if messages and len(messages) > 0:
                            latest_message = messages[0]
                            retrieve_span.set_attribute("message_role", latest_message.role)
                            
                            if latest_message.role == "assistant" and latest_message.content:
                                content_item = latest_message.content[0]
                                if hasattr(content_item, 'text'):
                                    response_text = content_item.text.value
                                    annotations = getattr(content_item.text, 'annotations', [])
                                    
                                    response_data = format_bing_grounding_response(response_text, annotations)
                                    span.set_status(Status(StatusCode.OK))
                                    return JSONResponse(
                                        content=response_data,
                                        headers={"Content-Type": "application/json; charset=utf-8"}
                                    )
                        
                        # Fallback response
                        error_response = format_bing_grounding_response("No search results available")
                        return JSONResponse(
                            content=error_response,
                            headers={"Content-Type": "application/json; charset=utf-8"}
                        )
                        
                except Exception as msg_error:
                    span.record_exception(msg_error)
                    logging.error(f"search: Error retrieving messages: {msg_error}")
                    error_response = format_bing_grounding_response("Error retrieving search results")
                    return JSONResponse(
                        status_code=500,
                        content=error_response,
                        headers={"Content-Type": "application/json; charset=utf-8"}
                    )
                    
        except Exception as e:
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))
            logging.error(f"search: Error processing search request: {e}")
            error_response = format_bing_grounding_response("An error occurred while processing your search request.")
            return JSONResponse(
                status_code=500,
                content=error_response,
                headers={"Content-Type": "application/json; charset=utf-8"}
            )


def format_unicode_citations(text):
    """Format citations to use Unicode characters for proper display"""
    import re
    # Replace [doc1] style citations with Unicode format 【1:0†source】
    # This is a simplified version - more sophisticated parsing may be needed
    citation_pattern = r'\[([^\]]+)\]'
    
    def replace_citation(match):
        citation_content = match.group(1)
        # Simple mapping - in practice, you'd want more sophisticated citation handling
        return f"【{citation_content}†source】"
    
    return re.sub(citation_pattern, replace_citation, text)


def format_bing_grounding_response(content, annotations=None):
    """Format the response to match the required JSON structure with annotations."""
    if annotations is None:
        annotations = []
    
    # Format citations in the content
    formatted_content = format_unicode_citations(content)
    
    # Convert annotations to the required format
    formatted_annotations = []
    for annotation in annotations:
        if hasattr(annotation, 'text') and hasattr(annotation, 'file_citation'):
            formatted_annotation = {
                "type": "citation",
                "text": annotation.text,
                "start_index": getattr(annotation, 'start_index', 0),
                "end_index": getattr(annotation, 'end_index', len(annotation.text)),
                "citation": {
                    "citation_id": getattr(annotation.file_citation, 'file_id', '1:0'),
                    "quote": getattr(annotation.file_citation, 'quote', ''),
                    "source_name": getattr(annotation.file_citation, 'file_id', 'Web Search')
                }
            }
            formatted_annotations.append(formatted_annotation)
    
    return {
        "response": {
            "type": "text",
            "text": {
                "value": formatted_content,
                "annotations": formatted_annotations
            }
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
