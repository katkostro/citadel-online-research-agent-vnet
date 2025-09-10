# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license. See LICENSE.md file in the project root for full license information.

import json
import logging
import os
from typing import Dict, List, Optional, Any
import aiohttp
import asyncio

logger = logging.getLogger(__name__)


class BingGroundingTool:
    """
    A tool for performing web searches using Bing Search API and providing grounded information.
    Optimized for the network-secured Azure AI Foundry environment.
    """

    def __init__(self, subscription_key: str = None, endpoint: str = "https://api.bing.microsoft.com/"):
        """
        Initialize the Bing Grounding Tool.
        
        Args:
            subscription_key: Bing Search API subscription key
            endpoint: Bing Search API endpoint
        """
        self.subscription_key = subscription_key or os.getenv('BING_SEARCH_API_KEY', '')
        self.endpoint = endpoint.rstrip('/')
        self.enabled = bool(self.subscription_key) and os.getenv('ENABLE_BING_SEARCH', 'false').lower() == 'true'
        
        if self.enabled:
            logger.info("BingGroundingTool initialized successfully")
        else:
            logger.info("BingGroundingTool initialized but disabled (no API key or not enabled)")

    async def search_web_async(self, query: str, count: int = 5, market: str = "en-US") -> List[Dict[str, Any]]:
        """
        Perform an async web search using Bing Search API.
        
        Args:
            query: The search query
            count: Number of results to return (max 50)
            market: Market code for localization
            
        Returns:
            List of search results with title, url, snippet, and display_url
        """
        if not self.enabled:
            return self._create_fallback_results(query)
            
        try:
            headers = {
                'Ocp-Apim-Subscription-Key': self.subscription_key,
                'User-Agent': 'Mozilla/5.0 (compatible; AzureAI-Agent/1.0)'
            }
            
            params = {
                'q': query,
                'count': min(count, 50),
                'mkt': market,
                'safeSearch': 'Moderate',
                'textDecorations': 'false',
                'textFormat': 'Raw'
            }
            
            async with aiohttp.ClientSession() as session:
                # Use standard Bing Search v7 endpoint
                search_url = f"{self.endpoint}/v7.0/search"
                
                async with session.get(search_url, headers=headers, params=params) as response:
                    if response.status == 200:
                        data = await response.json()
                        return self._parse_search_results(data)
                    elif response.status == 401:
                        logger.warning(f"Bing API authentication failed. Status: {response.status}")
                        return self._create_fallback_results(query)
                    else:
                        logger.error(f"Bing API request failed. Status: {response.status}")
                        return self._create_fallback_results(query)
                        
        except Exception as e:
            logger.error(f"Error performing web search: {e}", exc_info=True)
            return self._create_fallback_results(query)

    def _create_fallback_results(self, query: str) -> List[Dict[str, Any]]:
        """
        Create fallback search results when Bing API is not available.
        
        Args:
            query: The original search query
            
        Returns:
            List with helpful guidance for finding current information
        """
        return [
            {
                'title': f'Search Configuration Notice: "{query}"',
                'url': 'https://www.bing.com/search?q=' + query.replace(' ', '+'),
                'snippet': f'I attempted to search for current information about "{query}" but the Bing Search API is not configured or enabled. To enable web search functionality, please configure the BING_SEARCH_API_KEY environment variable with a valid Bing Search v7 API key and set ENABLE_BING_SEARCH=true.',
                'display_url': 'Configuration Required',
                'date_last_crawled': '2025-09-09',
                'language': 'en'
            },
            {
                'title': 'Alternative Search Options',
                'url': 'https://azure.microsoft.com/services/cognitive-services/bing-web-search-api/',
                'snippet': 'For immediate information needs, please search manually using: Bing.com, Google.com, or specialized sources. To configure Bing Search for this AI agent, obtain a Bing Search v7 API key from the Azure Portal and configure it as described in the deployment documentation.',
                'display_url': 'Manual Search Recommended',
                'date_last_crawled': '2025-09-09',
                'language': 'en'
            }
        ]

    def _parse_search_results(self, data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Parse Bing search API response into standardized format.
        
        Args:
            data: Raw response from Bing Search API
            
        Returns:
            List of parsed search results
        """
        results = []
        
        if 'webPages' in data and 'value' in data['webPages']:
            for item in data['webPages']['value']:
                result = {
                    'title': item.get('name', ''),
                    'url': item.get('url', ''),
                    'snippet': item.get('snippet', ''),
                    'display_url': item.get('displayUrl', ''),
                    'date_last_crawled': item.get('dateLastCrawled', ''),
                    'language': item.get('language', 'en')
                }
                results.append(result)
        
        logger.info(f"Bing search returned {len(results)} results")
        return results

    def format_search_results(self, results: List[Dict[str, Any]], max_results: int = 5) -> str:
        """
        Format search results for use in agent responses.
        
        Args:
            results: List of search results
            max_results: Maximum number of results to include
            
        Returns:
            Formatted string of search results
        """
        if not results:
            return "No search results found."
        
        formatted_results = []
        for i, result in enumerate(results[:max_results], 1):
            formatted_result = f"""
**Result {i}:**
- **Title:** {result.get('title', 'N/A')}
- **URL:** {result.get('url', 'N/A')}
- **Summary:** {result.get('snippet', 'N/A')}
- **Display URL:** {result.get('display_url', 'N/A')}
"""
            formatted_results.append(formatted_result.strip())
        
        return "\n\n".join(formatted_results)

    async def get_grounded_information(self, query: str, context: str = "") -> Dict[str, Any]:
        """
        Get grounded information by searching the web and combining results.
        
        Args:
            query: The search query
            context: Additional context to help with the search
            
        Returns:
            Dictionary containing search results and grounded information
        """
        try:
            # Enhance query with context if provided
            enhanced_query = f"{query} {context}".strip() if context else query
            
            # Perform web search
            search_results = await self.search_web_async(enhanced_query, count=5)
            
            # Format results for agent consumption
            formatted_results = self.format_search_results(search_results)
            
            # Create grounded information response
            grounded_info = {
                'query': query,
                'enhanced_query': enhanced_query,
                'search_results': search_results,
                'formatted_results': formatted_results,
                'sources_count': len(search_results),
                'timestamp': asyncio.get_event_loop().time() if asyncio.get_event_loop().is_running() else 0,
                'enabled': self.enabled
            }
            
            logger.info(f"Generated grounded information for query: {query}")
            return grounded_info
            
        except Exception as e:
            logger.error(f"Error generating grounded information: {e}", exc_info=True)
            return {
                'query': query,
                'error': str(e),
                'search_results': [],
                'formatted_results': "Error retrieving search results.",
                'sources_count': 0,
                'enabled': self.enabled
            }


def create_bing_grounding_function_definition() -> Dict[str, Any]:
    """
    Create function definition for Azure AI Foundry agent tools.
    
    Returns:
        Function definition dictionary for Bing grounding search
    """
    return {
        "type": "function",
        "function": {
            "name": "search_web",
            "description": "Search the web for current information using Bing Search API. Use this when you need up-to-date information, current events, recent news, or real-time data that may not be in your knowledge base.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "The search query to find information about. Be specific and include relevant keywords."
                    },
                    "context": {
                        "type": "string", 
                        "description": "Additional context to help refine the search (optional)."
                    }
                },
                "required": ["query"]
            }
        }
    }


async def execute_bing_search_function(function_call: Dict[str, Any], bing_tool: BingGroundingTool) -> str:
    """
    Execute the Bing search function call.
    
    Args:
        function_call: The function call from the agent
        bing_tool: The BingGroundingTool instance
        
    Returns:
        JSON string with search results
    """
    try:
        arguments = json.loads(function_call.get('arguments', '{}'))
        query = arguments.get('query', '')
        context = arguments.get('context', '')
        
        if not query:
            return json.dumps({'error': 'Query parameter is required'})
        
        grounded_info = await bing_tool.get_grounded_information(query, context)
        return json.dumps(grounded_info, indent=2)
        
    except Exception as e:
        logger.error(f"Error executing Bing search function: {e}", exc_info=True)
        return json.dumps({'error': f'Failed to execute search: {str(e)}'})
