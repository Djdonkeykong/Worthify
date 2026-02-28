import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'

const REVENUECAT_WEBHOOK_AUTH = Deno.env.get('REVENUECAT_WEBHOOK_AUTH')

interface RevenueCatWebhookEvent {
  api_version: string
  event: {
    type: string
    app_user_id: string
    product_id: string
    period_type: string
    purchased_at_ms: number
    expiration_at_ms: number | null
    environment: string
    entitlement_ids: string[]
    presented_offering_id: string | null
    transaction_id: string
    original_transaction_id: string
    is_trial_conversion: boolean
    store: string
  }
}

serve(async (req) => {
  try {
    // Verify Authorization header for security
    const authHeader = req.headers.get('Authorization')

    if (REVENUECAT_WEBHOOK_AUTH) {
      if (!authHeader) {
        console.error('[RevenueCat Webhook] Missing Authorization header')
        return new Response(JSON.stringify({ error: 'Unauthorized - Missing Authorization header' }), {
          status: 401,
          headers: { 'Content-Type': 'application/json' },
        })
      }

      if (authHeader !== REVENUECAT_WEBHOOK_AUTH) {
        console.error('[RevenueCat Webhook] Invalid Authorization header')
        return new Response(JSON.stringify({ error: 'Unauthorized - Invalid Authorization header' }), {
          status: 401,
          headers: { 'Content-Type': 'application/json' },
        })
      }

      console.log('[RevenueCat Webhook] Authorization verified successfully')
    } else {
      console.warn('[RevenueCat Webhook] REVENUECAT_WEBHOOK_AUTH not set - running without authorization verification')
    }

    const body = await req.text()
    const webhookData: RevenueCatWebhookEvent = JSON.parse(body)
    const eventType = webhookData.event.type
    const userId = webhookData.event.app_user_id
    const productId = webhookData.event.product_id
    const periodType = webhookData.event.period_type
    const expirationAtMs = webhookData.event.expiration_at_ms
    const isTrialConversion = webhookData.event.is_trial_conversion

    console.log(`[RevenueCat Webhook] Received event: ${eventType} for user ${userId}`)
    console.log(`[RevenueCat Webhook] Product: ${productId}, Period: ${periodType}, Trial Conversion: ${isTrialConversion}`)

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Calculate subscription details
    const isTrial = periodType === 'TRIAL' || periodType === 'INTRO'
    const expiresAt = expirationAtMs
      ? new Date(expirationAtMs).toISOString()
      : null

    console.log(`[RevenueCat Webhook] Is Trial: ${isTrial}, Expires At: ${expiresAt}`)

    // Handle different event types
    switch (eventType) {
      case 'INITIAL_PURCHASE':
      case 'RENEWAL':
      case 'NON_RENEWING_PURCHASE':
        // User has an active subscription
        await supabase.from('users').upsert({
          id: userId,
          subscription_status: 'active',
          subscription_product_id: productId,
          subscription_expires_at: expiresAt,
          is_trial: isTrial,
          revenue_cat_user_id: userId,
          subscription_last_synced_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }, { onConflict: 'id' })

        console.log(`[RevenueCat Webhook] Updated user ${userId} to active subscription (trial: ${isTrial})`)
        break

      case 'CANCELLATION':
        // Subscription cancelled but may still be active until expiration
        await supabase.from('users').update({
          subscription_status: 'active', // Still active until expires
          subscription_expires_at: expiresAt,
          subscription_last_synced_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }).eq('id', userId)

        console.log(`[RevenueCat Webhook] Marked subscription as cancelled for user ${userId}`)
        break

      case 'EXPIRATION':
      case 'BILLING_ISSUE':
        // Subscription has expired or billing failed
        await supabase.from('users').update({
          subscription_status: 'expired',
          subscription_expires_at: expiresAt,
          is_trial: false, // No longer in trial
          subscription_last_synced_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }).eq('id', userId)

        console.log(`[RevenueCat Webhook] Marked subscription as expired for user ${userId}`)
        break

      case 'PRODUCT_CHANGE':
        // User changed subscription plan
        await supabase.from('users').update({
          subscription_product_id: productId,
          subscription_expires_at: expiresAt,
          is_trial: isTrial,
          subscription_last_synced_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }).eq('id', userId)

        console.log(`[RevenueCat Webhook] Updated product to ${productId} for user ${userId}`)
        break

      case 'TEST':
        console.log(`[RevenueCat Webhook] Test event received - webhook is working correctly`)
        break

      default:
        console.log(`[RevenueCat Webhook] Unhandled event type: ${eventType}`)
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('[RevenueCat Webhook] Error processing webhook:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
