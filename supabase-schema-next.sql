-- Черновая схема следующего серверного этапа .B.A.D.Workshop.
-- ВАЖНО: private_segment_notes отделены от публичных комментариев,
-- чтобы руководитель технически не мог их прочитать через клиентское приложение.

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  position text,
  role text not null default 'employee' check (role in ('employee','manager')),
  approved boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  active boolean not null default true,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists pay_rules (
  employee_id uuid primary key references profiles(id) on delete cascade,
  base_shift numeric not null default 0,
  base_hours numeric not null default 12,
  overtime_hour numeric not null default 0,
  night_pct numeric not null default 0,
  rest_threshold_hours numeric not null default 8,
  short_rest_bonus numeric not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists shifts (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references profiles(id),
  started_at timestamptz not null,
  ended_at timestamptz,
  status text not null default 'active' check (status in ('active','submitted','approved','returned')),
  created_at timestamptz not null default now()
);

create table if not exists work_segments (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null references shifts(id) on delete cascade,
  project_id uuid not null references projects(id),
  work_type text not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  employee_comment text,
  manager_reply text,
  manager_reply_by uuid references profiles(id),
  manager_reply_at timestamptz
);

create table if not exists private_segment_notes (
  id uuid primary key default gen_random_uuid(),
  segment_id uuid not null references work_segments(id) on delete cascade,
  employee_id uuid not null references profiles(id) on delete cascade,
  note text not null,
  updated_at timestamptz not null default now(),
  unique(segment_id, employee_id)
);

create table if not exists employee_expenses (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid references shifts(id) on delete set null,
  employee_id uuid not null references profiles(id),
  project_id uuid not null references projects(id),
  category text not null,
  amount numeric not null,
  comment text,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

create table if not exists project_costs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id),
  category text not null,
  amount numeric not null,
  comment text,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

-- RLS для private_segment_notes обязательно должен разрешать SELECT/INSERT/UPDATE/DELETE
-- только когда employee_id = auth.uid(). Не добавлять manager bypass к этой таблице.
