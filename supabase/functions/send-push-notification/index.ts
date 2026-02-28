// Supabase Edge Function: Send push notifications via Firebase Cloud Messaging (FCM V1 API)
// This function sends notifications to users based on their FCM tokens

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface NotificationRequest {
  user_id?: string  // Send to specific user
  user_ids?: string[]  // Send to multiple users
  title: string
  body: string
  data?: Record<string, string>  // Custom data payload
}

// Get OAuth2 access token for FCM V1 API
async function getAccessToken(serviceAccount: any): Promise<string> {
  const jwtHeader = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))

  const now = Math.floor(Date.now() / 1000)
  const jwtClaimSet = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now
  }

  const jwtClaimSetEncoded = btoa(JSON.stringify(jwtClaimSet))
  const signatureInput = `${jwtHeader}.${jwtClaimSetEncoded}`

  // Import private key
  const privateKey = serviceAccount.private_key
  const pemHeader = '-----BEGIN PRIVATE KEY-----'
  const pemFooter = '-----END PRIVATE KEY-----'
  const pemContents = privateKey.substring(pemHeader.length, privateKey.length - pemFooter.length).trim()
  const binaryDer = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0))

  const key = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  // Sign the JWT
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signatureInput)
  )

  const signatureEncoded = btoa(String.fromCharCode(...new Uint8Array(signature)))
  const jwt = `${signatureInput}.${signatureEncoded}`

  // Exchange JWT for access token
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`
  })

  const tokenData = await tokenResponse.json()
  return tokenData.access_token
}

serve(async (req) => {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get Firebase Service Account from environment variable
    const firebaseServiceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!firebaseServiceAccountJson) {
      throw new Error('FIREBASE_SERVICE_ACCOUNT not configured')
    }

    const serviceAccount = JSON.parse(firebaseServiceAccountJson)
    const projectId = serviceAccount.project_id

    // Parse request body
    const { user_id, user_ids, title, body, data }: NotificationRequest = await req.json()

    if (!user_id && (!user_ids || user_ids.length === 0)) {
      return new Response(
        JSON.stringify({ error: 'user_id or user_ids required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Get FCM tokens for the user(s)
    let tokensQuery = supabase
      .from('fcm_tokens')
      .select('token, user_id')

    if (user_id) {
      tokensQuery = tokensQuery.eq('user_id', user_id)
    } else if (user_ids) {
      tokensQuery = tokensQuery.in('user_id', user_ids)
    }

    const { data: tokens, error: tokensError } = await tokensQuery

    if (tokensError) {
      throw tokensError
    }

    if (!tokens || tokens.length === 0) {
      console.log('[Push] No FCM tokens found for user(s)')
      return new Response(
        JSON.stringify({ success: false, message: 'No FCM tokens found' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`[Push] Found ${tokens.length} FCM token(s)`)

    // Get OAuth2 access token
    const accessToken = await getAccessToken(serviceAccount)

    // Send notification to each token using FCM V1 API
    const results = []
    for (const tokenRecord of tokens) {
      const { token } = tokenRecord

      const fcmPayload = {
        message: {
          token: token,
          notification: {
            title,
            body,
          },
          data: data || {},
          apns: {
            payload: {
              aps: {
                sound: 'default'
              }
            }
          },
          android: {
            priority: 'high',
            notification: {
              sound: 'default'
            }
          }
        }
      }

      const fcmResponse = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${accessToken}`,
          },
          body: JSON.stringify(fcmPayload),
        }
      )

      const fcmResult = await fcmResponse.json()
      results.push(fcmResult)

      console.log(`[Push] Sent to token ${token.substring(0, 20)}...: ${JSON.stringify(fcmResult)}`)
    }

    return new Response(
      JSON.stringify({
        success: true,
        sent_count: tokens.length,
        results
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('[Push] Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
