-- Черновая схема для следующего серверного этапа .B.A.D.Workshop v4.
-- Не обязательна для локальной тестовой версии.
create table if not exists profiles (
  id uuid primary key,
  full_name text not null,
  position text,
  role text not null check (role in ('manager','employee')),
  approved boolean not null default false
);

create table if not exists projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists pay_rules (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  shift_type text not null check (shift_type in ('base','project','other')),
  shift_rate numeric not null default 0,
  overtime_rate numeric not null default 0,
  unique(employee_id, shift_type)
);

create table if not exists project_overtime_rates (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  employee_id uuid not null,
  shift_type text not null,
  overtime_rate numeric not null default 0,
  unique(project_id, employee_id, shift_type)
);

create table if not exists shifts (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  shift_type text not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  status text not null default 'active'
);

create table if not exists work_segments (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null,
  project_id uuid not null,
  work_type text not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  employee_comment text,
  manager_reply text
);

-- Приватные заметки должны быть отдельной таблицей с RLS: читать/писать может только владелец.
create table if not exists private_segment_notes (
  id uuid primary key default gen_random_uuid(),
  segment_id uuid not null,
  employee_id uuid not null,
  note text
);

create table if not exists employee_expenses (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null,
  employee_id uuid not null,
  project_id uuid not null,
  category text not null,
  amount numeric not null,
  comment text,
  created_at timestamptz not null default now()
);

create table if not exists employee_payments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  amount numeric not null,
  comment text,
  paid_at timestamptz not null default now()
);

create table if not exists project_costs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  category text not null,
  amount numeric not null,
  comment text,
  created_at timestamptz not null default now()
);

create table if not exists project_income (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  income_type text not null check (income_type in ('estimate','received')),
  amount numeric not null,
  comment text,
  created_at timestamptz not null default now()
);
