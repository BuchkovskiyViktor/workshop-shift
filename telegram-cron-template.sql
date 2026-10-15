-- OPTIONAL: run only after deploying supabase/functions/bad-workshop-telegram
-- and adding TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID and CRON_SECRET to Edge Function secrets.
-- Replace PROJECT_REF and CRON_SECRET_VALUE before running.

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

-- Store a long random secret used only to authorize the scheduled request.
select vault.create_secret('CRON_SECRET_VALUE', 'bad_workshop_cron_secret', 'Authorization secret for .B.A.D.Workshop task reminders');

-- If the job already exists, unschedule it first from the Cron page or run:
-- select cron.unschedule(jobid) from cron.job where jobname='bad-workshop-task-reminders';
select cron.schedule(
  'bad-workshop-task-reminders',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://PROJECT_REF.supabase.co/functions/v1/bad-workshop-telegram',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name='bad_workshop_cron_secret' limit 1)
    ),
    body := '{"action":"dispatch_reminders"}'::jsonb
  );
  $$
);
