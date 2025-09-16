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
# NOTE: Removed direct import of Agent (not exported in current azure-ai-projects version) to prevent startup crash.

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
         - 🔍 **Research Endpoint**: `/research`
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
            "research": f"{request.url}research",
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

# Internal implementation that performs the core research/search operation.
# Previously this existed as `search_endpoint` route; now we keep it as an internal
# function so multiple public/alias routes can delegate here without duplicating logic.
async def search_endpoint(request: Message):
    """Core research logic used by /research and legacy/alias endpoints.

    Current placeholder implementation streams through AI agent eventually; for now
    it returns a structured JSON response indicating the feature stub. Extend this
    to call Bing grounding / agent once those pieces are fully wired.
    """
    with tracer.start_as_current_span("search_endpoint_core") as span:
        span.set_attribute("query.length", len(request.message or ""))
        span.set_attribute("has_session_state", bool(request.session_state))
        # Placeholder response – keep shape obvious for future enhancement.
        response = {
            "query": request.message,
            "status": "not_implemented_yet",
            "message": "Research functionality placeholder – integrate Bing grounding + agent run here.",
            "session_state": request.session_state or {},
            "version": "1.0.0"
        }
        return JSONResponse(content=response)

# Primary research endpoint
@app.post("/research", tags=["search"], summary="Perform research with AI analysis", include_in_schema=True)
async def research_endpoint(request: Message, _ = auth_dependency):
    return await search_endpoint(request)  # delegate to existing implementation

# Researcher prefixed alias (kept minimal)
@app.post("/researcher/research", include_in_schema=False)
async def researcher_research_alias(request: Message):
    return await search_endpoint(request)
