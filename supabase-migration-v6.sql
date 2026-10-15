-- .B.A.D.Workshop v6 incremental migration
-- Run once in Supabase SQL Editor on the EXISTING v5 project.
-- This migration preserves existing projects, profiles, shifts and financial records.

begin;

-- Project editing
alter table public.projects add column if not exists description text;

-- Manager review, manual final amount, and rejection/return reasons
alter table public.shifts add column if not exists manager_pay_override numeric(12,2);
alter table public.shifts add column if not exists rejection_reason text;
alter table public.shifts add column if not exists reviewed_by uuid references public.profiles(id) on delete set null;
alter table public.shifts add column if not exists reviewed_at timestamptz;

-- Ensure manager-editable segment fields exist (safe if already present in v5)
alter table public.shift_segments add column if not exists manager_base_rate_override numeric(12,2);
alter table public.shift_segments add column if not exists manager_overtime_rate_override numeric(12,2);
alter table public.shift_segments add column if not exists manager_reply_by uuid references public.profiles(id) on delete set null;
alter table public.shift_segments add column if not exists manager_reply_at timestamptz;

-- Per-employee feature controls and default shift type
alter table public.profiles add column if not exists features jsonb not null default '{"todos":true,"shift_type":true,"expenses":true,"comments":true,"private_notes":true,"work_switch":true}'::jsonb;
alter table public.profiles add column if not exists default_shift_type text not null default 'base';
update public.profiles set features='{"todos":true,"shift_type":true,"expenses":true,"comments":true,"private_notes":true,"work_switch":true}'::jsonb where features is null;

-- Todo descriptions and scheduled reminders
alter table public.todos add column if not exists description text not null default '';
alter table public.todos add column if not exists reminder_at timestamptz;
alter table public.todos add column if not exists telegram_reminder boolean not null default false;
alter table public.todos add column if not exists reminder_sent_at timestamptz;

-- Add custom shift type rates for types created by the manager
create table if not exists public.shift_type_rates (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  shift_type text not null,
  shift_rate numeric(12,2) not null default 0,
  overtime_rate numeric(12,2) not null default 0,
  updated_at timestamptz not null default now(),
  unique(employee_id, shift_type)
);
alter table public.shift_type_rates enable row level security;

-- Editable dropdown lists. option_key is stable so renaming a label does not rewrite old records.
create table if not exists public.app_options (
  id uuid primary key default gen_random_uuid(),
  list_key text not null,
  option_key text not null,
  label text not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(list_key, option_key)
);
alter table public.app_options enable row level security;

-- Task discussion thread / explanations beneath tasks
create table if not exists public.todo_comments (
  id uuid primary key default gen_random_uuid(),
  todo_id uuid not null references public.todos(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
alter table public.todo_comments enable row level security;

-- Seed default lists without overwriting any existing customisations.
insert into public.app_options(list_key, option_key, label, sort_order, active) values
 ('shift_types','base','Базовая',10,true),
 ('shift_types','project','Проектная',20,true),
 ('shift_types','other','Другое',30,true),
 ('work_types','Изготовление','Изготовление',10,true),
 ('work_types','Сборка','Сборка',20,true),
 ('work_types','Сварка','Сварка',30,true),
 ('work_types','Столярка','Столярка',40,true),
 ('work_types','Покраска','Покраска',50,true),
 ('work_types','Бутафория','Бутафория',60,true),
 ('work_types','Погрузка','Погрузка',70,true),
 ('work_types','Разгрузка','Разгрузка',80,true),
 ('work_types','Логистика','Логистика',90,true),
 ('work_types','Монтаж','Монтаж',100,true),
 ('work_types','Демонтаж','Демонтаж',110,true),
 ('work_types','Работа на площадке','Работа на площадке',120,true),
 ('work_types','Закупка','Закупка',130,true),
 ('work_types','Прочее','Прочее',140,true),
 ('employee_expense_categories','Личный транспорт','Личный транспорт',10,true),
 ('employee_expense_categories','Такси','Такси',20,true),
 ('employee_expense_categories','Обед','Обед',30,true),
 ('employee_expense_categories','Закупки','Закупки',40,true),
 ('employee_expense_categories','Материалы','Материалы',50,true),
 ('employee_expense_categories','Парковка','Парковка',60,true),
 ('employee_expense_categories','Прочее','Прочее',70,true),
 ('analytics_categories','Транспорт','Транспорт',10,true),
 ('analytics_categories','Обеды','Обеды',20,true),
 ('analytics_categories','Закупки','Закупки',30,true),
 ('analytics_categories','Материалы','Материалы',40,true),
 ('analytics_categories','Парковка','Парковка',50,true),
 ('analytics_categories','Аренда','Аренда',60,true),
 ('analytics_categories','Подрядчики','Подрядчики',70,true),
 ('analytics_categories','Прочее','Прочее',80,true),
 ('direct_cost_categories','Транспорт','Транспорт',10,true),
 ('direct_cost_categories','Обеды','Обеды',20,true),
 ('direct_cost_categories','Закупки','Закупки',30,true),
 ('direct_cost_categories','Материалы','Материалы',40,true),
 ('direct_cost_categories','Парковка','Парковка',50,true),
 ('direct_cost_categories','Аренда','Аренда',60,true),
 ('direct_cost_categories','Подрядчики','Подрядчики',70,true),
 ('direct_cost_categories','Прочее','Прочее',80,true)
on conflict (list_key, option_key) do nothing;

-- Update the existing status CHECK constraint to support explicit rejection.
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid='public.shifts'::regclass and contype='c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.shifts drop constraint %I', c.conname);
  end loop;
  alter table public.shifts add constraint shifts_status_v6_check
    check (status in ('active','submitted','approved','returned','rejected'));
end $$;

-- RLS helper: manager role is read from the server-side profile.
create or replace function public.bad_v6_is_manager()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='manager' and p.approved=true); $$;

-- Dropdown lists: approved users may read; only managers may change them.
drop policy if exists bad_v6_options_read on public.app_options;
create policy bad_v6_options_read on public.app_options for select to authenticated
  using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.approved=true));
drop policy if exists bad_v6_options_manager_write on public.app_options;
create policy bad_v6_options_manager_write on public.app_options for all to authenticated
  using (public.bad_v6_is_manager()) with check (public.bad_v6_is_manager());

-- Custom rates: employees can read their own rates; managers can manage all rates.
drop policy if exists bad_v6_shift_rates_read on public.shift_type_rates;
create policy bad_v6_shift_rates_read on public.shift_type_rates for select to authenticated
  using (employee_id=auth.uid() or public.bad_v6_is_manager());
drop policy if exists bad_v6_shift_rates_manager_write on public.shift_type_rates;
create policy bad_v6_shift_rates_manager_write on public.shift_type_rates for all to authenticated
  using (public.bad_v6_is_manager()) with check (public.bad_v6_is_manager());

-- Task comments: only people related to the task and managers may read/post.
drop policy if exists bad_v6_todo_comments_read on public.todo_comments;
create policy bad_v6_todo_comments_read on public.todo_comments for select to authenticated
  using (public.bad_v6_is_manager() or author_id=auth.uid() or exists(
    select 1 from public.todos t where t.id=todo_id and (t.assignee_id=auth.uid() or t.created_by=auth.uid())
  ));
drop policy if exists bad_v6_todo_comments_insert on public.todo_comments;
create policy bad_v6_todo_comments_insert on public.todo_comments for insert to authenticated
  with check (author_id=auth.uid() and (public.bad_v6_is_manager() or exists(
    select 1 from public.todos t where t.id=todo_id and (t.assignee_id=auth.uid() or t.created_by=auth.uid())
  )));
drop policy if exists bad_v6_todo_comments_update on public.todo_comments;
create policy bad_v6_todo_comments_update on public.todo_comments for update to authenticated
  using (public.bad_v6_is_manager() or author_id=auth.uid()) with check (public.bad_v6_is_manager() or author_id=auth.uid());
drop policy if exists bad_v6_todo_comments_delete on public.todo_comments;
create policy bad_v6_todo_comments_delete on public.todo_comments for delete to authenticated
  using (public.bad_v6_is_manager() or author_id=auth.uid());

-- Enforce the employee feature switches on writes too, not just by hiding buttons.
create or replace function public.bad_v6_enforce_employee_features()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_role text; v_features jsonb; v_default_type text; v_shift_employee uuid;
begin
  if auth.uid() is null then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  select p.role, coalesce(p.features,'{}'::jsonb), coalesce(p.default_shift_type,'base')
    into v_role,v_features,v_default_type from public.profiles p where p.id=auth.uid();
  if v_role='manager' then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  if tg_table_name='expenses' then
    if coalesce((v_features->>'expenses')::boolean,true)=false then raise exception 'Внесение расходов отключено руководителем'; end if;
  elsif tg_table_name='todos' or tg_table_name='todo_comments' then
    if coalesce((v_features->>'todos')::boolean,true)=false then raise exception 'Раздел «Дела» отключён руководителем'; end if;
  elsif tg_table_name='segment_private_notes' then
    if coalesce((v_features->>'private_notes')::boolean,true)=false then raise exception 'Приватные заметки отключены руководителем'; end if;
  elsif tg_table_name='shift_segments' then
    select s.employee_id into v_shift_employee from public.shifts s where s.id=new.shift_id;
    if v_shift_employee=auth.uid() then
      if coalesce((v_features->>'work_switch')::boolean,true)=false and tg_op='INSERT' and exists(select 1 from public.shift_segments s where s.shift_id=new.shift_id) then raise exception 'Смена участка отключена руководителем'; end if;
      if coalesce((v_features->>'shift_type')::boolean,true)=false then
        if tg_op='INSERT' and new.shift_type is distinct from v_default_type then raise exception 'Выбор типа смены отключён руководителем'; end if;
        if tg_op='UPDATE' and new.shift_type is distinct from old.shift_type then raise exception 'Выбор типа смены отключён руководителем'; end if;
      end if;
      if coalesce((v_features->>'comments')::boolean,true)=false then
        if tg_op='INSERT' and coalesce(new.employee_comment,'')<>'' then raise exception 'Комментарии отключены руководителем'; end if;
        if tg_op='UPDATE' and new.employee_comment is distinct from old.employee_comment then raise exception 'Комментарии отключены руководителем'; end if;
      end if;
    end if;
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end $$;

drop trigger if exists bad_v6_guard_expenses on public.expenses;
create trigger bad_v6_guard_expenses before insert or update on public.expenses for each row execute function public.bad_v6_enforce_employee_features();
drop trigger if exists bad_v6_guard_todos on public.todos;
create trigger bad_v6_guard_todos before insert or update on public.todos for each row execute function public.bad_v6_enforce_employee_features();
drop trigger if exists bad_v6_guard_todo_comments on public.todo_comments;
create trigger bad_v6_guard_todo_comments before insert or update on public.todo_comments for each row execute function public.bad_v6_enforce_employee_features();
drop trigger if exists bad_v6_guard_private_notes on public.segment_private_notes;
create trigger bad_v6_guard_private_notes before insert or update on public.segment_private_notes for each row execute function public.bad_v6_enforce_employee_features();
drop trigger if exists bad_v6_guard_segments on public.shift_segments;
create trigger bad_v6_guard_segments before insert or update on public.shift_segments for each row execute function public.bad_v6_enforce_employee_features();

-- Protect manager-only fields even if a client bypasses the visible UI.
create or replace function public.bad_v6_guard_shift_manager_fields()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_role text;
begin
  if auth.uid() is null then return new; end if;
  select role into v_role from public.profiles where id=auth.uid();
  if v_role='manager' then return new; end if;
  if old.employee_id is distinct from auth.uid() then raise exception 'Недостаточно прав на изменение смены'; end if;
  if new.employee_id is distinct from old.employee_id or new.started_at is distinct from old.started_at then raise exception 'Начало смены и сотрудник меняются только руководителем'; end if;
  if new.manager_pay_override is distinct from old.manager_pay_override or new.manager_note is distinct from old.manager_note or new.approved_by is distinct from old.approved_by or new.approved_at is distinct from old.approved_at or (new.rejection_reason is distinct from old.rejection_reason and not (old.status='returned' and new.status='submitted' and new.rejection_reason is null)) or new.reviewed_by is distinct from old.reviewed_by or new.reviewed_at is distinct from old.reviewed_at then raise exception 'Поля проверки смены меняет только руководитель'; end if;
  if new.status not in ('active','submitted') then raise exception 'Статус смены может менять только руководитель'; end if;
  if old.status not in ('active','returned') and (new.status is distinct from old.status or new.ended_at is distinct from old.ended_at) then raise exception 'Отправленная смена доступна для правки только руководителю'; end if;
  return new;
end $$;
drop trigger if exists bad_v6_guard_shift_manager_fields on public.shifts;
create trigger bad_v6_guard_shift_manager_fields before update on public.shifts for each row execute function public.bad_v6_guard_shift_manager_fields();

create or replace function public.bad_v6_guard_segment_manager_fields()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_role text; v_shift_employee uuid;
begin
  if auth.uid() is null then return new; end if;
  select role into v_role from public.profiles where id=auth.uid();
  if v_role='manager' then return new; end if;
  select employee_id into v_shift_employee from public.shifts where id=old.shift_id;
  if v_shift_employee is distinct from auth.uid() then raise exception 'Недостаточно прав на изменение участка'; end if;
  if new.shift_id is distinct from old.shift_id or new.project_id is distinct from old.project_id or new.work_type is distinct from old.work_type or new.shift_type is distinct from old.shift_type or new.started_at is distinct from old.started_at then raise exception 'Проект, вид работы, тип и начало участка меняет только руководитель'; end if;
  if new.manager_base_rate_override is distinct from old.manager_base_rate_override or new.manager_overtime_rate_override is distinct from old.manager_overtime_rate_override or new.manager_reply is distinct from old.manager_reply or new.manager_reply_by is distinct from old.manager_reply_by or new.manager_reply_at is distinct from old.manager_reply_at then raise exception 'Ставки и ответы руководителя изменяет только руководитель'; end if;
  return new;
end $$;
drop trigger if exists bad_v6_guard_segment_manager_fields on public.shift_segments;
create trigger bad_v6_guard_segment_manager_fields before update on public.shift_segments for each row execute function public.bad_v6_guard_segment_manager_fields();

create or replace function public.bad_v6_guard_expense_manager_fields()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_role text;
begin
  if auth.uid() is null then return new; end if;
  select role into v_role from public.profiles where id=auth.uid();
  if v_role='manager' then return new; end if;
  if tg_op='UPDATE' and old.employee_id is distinct from auth.uid() then raise exception 'Недостаточно прав на изменение расхода'; end if;
  if tg_op='INSERT' and new.employee_id is distinct from auth.uid() then raise exception 'Нельзя создавать расход за другого сотрудника'; end if;
  if tg_op='INSERT' and new.status is distinct from 'pending' then raise exception 'Подтвердить расход может только руководитель'; end if;
  if tg_op='UPDATE' then
    if old.status<>'pending' then raise exception 'Проверенный расход меняет только руководитель'; end if;
    if new.status is distinct from old.status or new.analytics_category is distinct from old.analytics_category or new.manager_note is distinct from old.manager_note then raise exception 'Статус и статья аналитики меняются только руководителем'; end if;
  end if;
  return new;
end $$;
drop trigger if exists bad_v6_guard_expense_manager_fields on public.expenses;
create trigger bad_v6_guard_expense_manager_fields before insert or update on public.expenses for each row execute function public.bad_v6_guard_expense_manager_fields();

create or replace function public.bad_v6_guard_profile_admin_fields()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_role text;
begin
  if auth.uid() is null or tg_op='INSERT' then return new; end if;
  select role into v_role from public.profiles where id=auth.uid();
  if v_role='manager' then return new; end if;
  if old.id=auth.uid() and (new.role is distinct from old.role or new.approved is distinct from old.approved or new.features is distinct from old.features or new.default_shift_type is distinct from old.default_shift_type) then raise exception 'Роль, доступ и функции назначает руководитель'; end if;
  return new;
end $$;
drop trigger if exists bad_v6_guard_profile_admin_fields on public.profiles;
create trigger bad_v6_guard_profile_admin_fields before update on public.profiles for each row execute function public.bad_v6_guard_profile_admin_fields();

create or replace function public.bad_v6_guard_todo_manager_fields()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_role text;
begin
  if auth.uid() is null then return new; end if;
  select role into v_role from public.profiles where id=auth.uid();
  if v_role='manager' then return new; end if;
  if tg_op='INSERT' and (new.created_by is distinct from auth.uid() or new.assignee_id is distinct from auth.uid()) then raise exception 'Сотрудник может создавать дела только для себя'; end if;
  if tg_op='UPDATE' then
    if old.assignee_id is distinct from auth.uid() and old.created_by is distinct from auth.uid() then raise exception 'Недостаточно прав на изменение дела'; end if;
    if new.created_by is distinct from old.created_by or new.assignee_id is distinct from old.assignee_id then raise exception 'Автор и исполнитель меняются только руководителем'; end if;
    if old.created_by is distinct from auth.uid() and (new.title is distinct from old.title or new.description is distinct from old.description or new.priority is distinct from old.priority or new.reminder_at is distinct from old.reminder_at or new.telegram_reminder is distinct from old.telegram_reminder) then raise exception 'Содержание назначенного дела меняет руководитель'; end if;
  end if;
  return new;
end $$;
drop trigger if exists bad_v6_guard_todo_manager_fields on public.todos;
create trigger bad_v6_guard_todo_manager_fields before insert or update on public.todos for each row execute function public.bad_v6_guard_todo_manager_fields();

-- Include the new tables in Realtime publication so clients can refresh promptly.
do $$
begin
  begin alter publication supabase_realtime add table public.app_options; exception when duplicate_object then null; when undefined_object then null; end;
  begin alter publication supabase_realtime add table public.shift_type_rates; exception when duplicate_object then null; when undefined_object then null; end;
  begin alter publication supabase_realtime add table public.todo_comments; exception when duplicate_object then null; when undefined_object then null; end;
end $$;

commit;

-- After the migration completes, confirm the new tables in Table Editor:
-- app_options, shift_type_rates, todo_comments.
