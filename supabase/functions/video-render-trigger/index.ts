import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // Auth check
  const authHeader = req.headers.get('Authorization')!
  const { data: { user }, error: authError } = await supabase.auth.getUser(
    authHeader.replace('Bearer ', '')
  )
  if (authError || !user) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401, headers: corsHeaders,
    })
  }

  const { compositionId, inputProps } = await req.json()
  const jobId = crypto.randomUUID()

  // Create render record
  const { error: insertError } = await supabase.from('video_renders').insert({
    user_id: user.id,
    job_id: jobId,
    video_type: compositionId,
    status: 'queued',
    payload: inputProps,
    created_at: new Date().toISOString(),
  })

  if (insertError) {
    return new Response(JSON.stringify({ error: insertError.message }), {
      status: 500, headers: corsHeaders,
    })
  }

  // Invoke Lambda asynchronously
  const lambdaArn = Deno.env.get('REMOTION_LAMBDA_ARN')
  if (lambdaArn) {
    // AWS Lambda invocation via REST (avoids AWS SDK in Deno)
    const lambdaPayload = JSON.stringify({ jobId, compositionId, inputProps, userId: user.id })
    const awsRegion = Deno.env.get('AWS_REGION') ?? 'ap-south-1'
    const lambdaUrl = `https://lambda.${awsRegion}.amazonaws.com/2015-03-31/functions/${encodeURIComponent(lambdaArn)}/invocations`

    // Fire-and-forget — don't await
    fetch(lambdaUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Amz-Invocation-Type': 'Event', // async
      },
      body: lambdaPayload,
    }).catch(console.error)
  }

  return new Response(
    JSON.stringify({
      jobId,
      statusUrl: `/functions/v1/video-status?jobId=${jobId}`,
    }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
})
