// Supabase Edge Function: Auto-detect user location from IP address
// Uses ipapi.co free tier (1000 requests/day, no API key needed)

import { serve } from 'https://deno.land/[email protected]/http/server.ts'

interface LocationResponse {
  country_code: string
  country_name: string
  city?: string
  region?: string
  latitude?: number
  longitude?: number
}

serve(async (req) => {
  // CORS headers
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }

  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get client IP from request headers
    const clientIP = req.headers.get('x-forwarded-for')?.split(',')[0].trim() ||
                     req.headers.get('x-real-ip') ||
                     'unknown'

    console.log(`[LocationDetect] Client IP: ${clientIP}`)

    // Call ipapi.co for geolocation (free tier: 1000 requests/day)
    const geoResponse = await fetch(`https://ipapi.co/${clientIP}/json/`)

    if (!geoResponse.ok) {
      throw new Error(`Geolocation API error: ${geoResponse.statusText}`)
    }

    const geoData = await geoResponse.json()

    // Map to our response format
    const locationData: LocationResponse = {
      country_code: geoData.country_code || 'US',
      country_name: geoData.country_name || 'United States',
      city: geoData.city,
      region: geoData.region,
      latitude: geoData.latitude,
      longitude: geoData.longitude,
    }

    console.log(`[LocationDetect] Detected: ${locationData.country_name} (${locationData.country_code})`)

    return new Response(
      JSON.stringify(locationData),
      {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      }
    )
  } catch (error) {
    console.error('[LocationDetect] Error:', error)

    // Fallback to US on error
    return new Response(
      JSON.stringify({
        country_code: 'US',
        country_name: 'United States',
        error: error.message,
      }),
      {
        status: 200, // Still return 200 with fallback
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      }
    )
  }
})
