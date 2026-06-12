export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    const searchParams = url.search;

    let targetUrl = '';

    // Route the requests to the respective APIs
    if (path === '/api/rates') {
      targetUrl = `https://api.frankfurter.dev/v2/rates${searchParams}`;
    } else if (path === '/api/quote') {
      targetUrl = `https://finnhub.io/api/v1/quote${searchParams}`;
    } else if (path === '/api/price') {
      targetUrl = `https://api.coingecko.com/api/v3/simple/price${searchParams}`;
    } else {
      return new Response(JSON.stringify({ error: 'Endpoint not found' }), { 
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Forward the original headers (which contain the API keys from the iOS app)
    const newRequest = new Request(targetUrl, {
      method: request.method,
      headers: request.headers,
    });

    try {
      const response = await fetch(newRequest);
      
      // Clone the response so we can modify headers if needed
      const newResponse = new Response(response.body, response);
      
      // Add CORS headers just in case it's called from a web client in the future
      newResponse.headers.set('Access-Control-Allow-Origin', '*');
      
      return newResponse;
    } catch (error) {
      return new Response(JSON.stringify({ error: 'Proxy fetch failed', details: error.message }), {
        status: 502,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  },
};
