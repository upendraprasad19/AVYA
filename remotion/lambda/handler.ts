import { renderMedia, selectComposition } from '@remotion/renderer';
import { createClient } from '@supabase/supabase-js';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

const s3 = new S3Client({ region: process.env.AWS_REGION ?? 'ap-south-1' });
const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_KEY!,
);

interface LambdaEvent {
  jobId: string;
  compositionId: string;
  inputProps: Record<string, unknown>;
  userId: string;
}

export const handler = async (event: LambdaEvent) => {
  const { jobId, compositionId, inputProps, userId } = event;
  const outputPath = path.join(os.tmpdir(), `${jobId}.mp4`);

  try {
    await supabase.from('video_renders').update({ status: 'rendering' }).eq('job_id', jobId);

    const composition = await selectComposition({
      serveUrl: process.env.REMOTION_SERVE_URL!,
      id: compositionId,
      inputProps,
    });

    await renderMedia({
      composition,
      serveUrl: process.env.REMOTION_SERVE_URL!,
      codec: 'h264',
      outputLocation: outputPath,
      inputProps,
      chromiumOptions: { disableWebSecurity: true },
      concurrency: 1,
    });

    const fileBuffer = fs.readFileSync(outputPath);
    const storagePath = `videos/${userId}/${jobId}.mp4`;

    const { error: uploadError } = await supabase.storage
      .from('user-videos')
      .upload(storagePath, fileBuffer, { contentType: 'video/mp4', upsert: true });

    if (uploadError) throw uploadError;

    const { data: urlData } = await supabase.storage
      .from('user-videos')
      .createSignedUrl(storagePath, 86400);

    await supabase.from('video_renders').update({
      status: 'ready',
      output_url: urlData?.signedUrl,
      output_storage_path: storagePath,
      file_size_bytes: fileBuffer.length,
      completed_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + 86400 * 1000).toISOString(),
    }).eq('job_id', jobId);

  } catch (err) {
    await supabase.from('video_renders').update({
      status: 'failed',
      completed_at: new Date().toISOString(),
    }).eq('job_id', jobId);
    throw err;
  } finally {
    if (fs.existsSync(outputPath)) fs.unlinkSync(outputPath);
  }
};
