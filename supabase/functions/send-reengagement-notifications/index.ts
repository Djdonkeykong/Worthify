// Supabase Edge Function: Send re-engagement notifications to inactive users
// This should be triggered by a cron job (e.g., daily)

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Create Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Find users who haven't uploaded in the last 7 days
    const sevenDaysAgo = new Date()
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7)

    console.log(`[ReEngagement] Looking for users inactive since ${sevenDaysAgo.toISOString()}`)

    // Get users with their last search date
    const { data: inactiveUsers, error: usersError } = await supabase
      .from('user_searches')
      .select('user_id, created_at')
      .order('created_at', { ascending: false })

    if (usersError) {
      throw usersError
    }

    if (!inactiveUsers || inactiveUsers.length === 0) {
      console.log('[ReEngagement] No users found')
      return new Response(
        JSON.stringify({ success: true, sent_count: 0, message: 'No users found' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Group by user_id and get the most recent search
    const userLastSearchMap = new Map<string, Date>()
    for (const search of inactiveUsers) {
      const userId = search.user_id
      const searchDate = new Date(search.created_at)

      if (!userLastSearchMap.has(userId)) {
        userLastSearchMap.set(userId, searchDate)
      }
    }

    // Filter to users who haven't searched in 7+ days
    const inactiveUserIds: string[] = []
    for (const [userId, lastSearch] of userLastSearchMap.entries()) {
      if (lastSearch < sevenDaysAgo) {
        inactiveUserIds.push(userId)
      }
    }

    console.log(`[ReEngagement] Found ${inactiveUserIds.length} inactive users`)

    if (inactiveUserIds.length === 0) {
      return new Response(
        JSON.stringify({ success: true, sent_count: 0, message: 'No inactive users' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check user preferences - only send to users who have notifications enabled
    const { data: preferences, error: prefsError } = await supabase
      .from('user_preferences')
      .select('user_id, notification_enabled, upload_reminders')
      .in('user_id', inactiveUserIds)

    if (prefsError) {
      console.error('[ReEngagement] Error fetching preferences:', prefsError)
    }

    // Filter to users who have upload reminders enabled
    const eligibleUserIds = inactiveUserIds.filter(userId => {
      const pref = preferences?.find(p => p.user_id === userId)
      // Default to true if no preference found
      return pref ? (pref.notification_enabled !== false && pref.upload_reminders !== false) : true
    })

    console.log(`[ReEngagement] ${eligibleUserIds.length} users have notifications enabled`)

    if (eligibleUserIds.length === 0) {
      return new Response(
        JSON.stringify({ success: true, sent_count: 0, message: 'No eligible users' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Call the send-push-notification function
    const notificationPayload = {
      user_ids: eligibleUserIds,
      title: 'Find your next look',
      body: "Haven't uploaded in a while? Discover new fashion items today!",
      data: {
        type: 're_engagement',
      }
    }

    const sendNotificationUrl = `${supabaseUrl}/functions/v1/send-push-notification`
    const notificationResponse = await fetch(sendNotificationUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${supabaseServiceKey}`,
      },
      body: JSON.stringify(notificationPayload),
    })

    const notificationResult = await notificationResponse.json()

    console.log(`[ReEngagement] Notification result:`, notificationResult)

    return new Response(
      JSON.stringify({
        success: true,
        inactive_users_count: inactiveUserIds.length,
        eligible_users_count: eligibleUserIds.length,
        notification_result: notificationResult
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('[ReEngagement] Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
