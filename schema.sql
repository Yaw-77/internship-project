-- Run once in Supabase SQL Editor. Requires Supabase Auth users.
create extension if not exists pgcrypto;
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null default '', email text not null default '',
 role text not null default 'STUDENT' check (role in ('ADMIN','STUDENT','UNIVERSITY_SUPERVISOR','INDUSTRY_SUPERVISOR')),
 department text, created_at timestamptz not null default now()
);
create table if not exists public.companies (
 id uuid primary key default gen_random_uuid(), name text not null,
 address text, contact_email text, created_at timestamptz not null default now()
);
create table if not exists public.placements (
 id uuid primary key default gen_random_uuid(), student_id uuid not null references public.profiles(id),
 company_id uuid not null references public.companies(id),
 university_supervisor_id uuid references public.profiles(id),
 industry_supervisor_id uuid references public.profiles(id),
 start_date date not null, end_date date not null,
 status text not null default 'ACTIVE' check(status in ('PENDING','ACTIVE','COMPLETED','REJECTED')),
 check(end_date >= start_date)
);
create table if not exists public.logbooks (
 id uuid primary key default gen_random_uuid(), placement_id uuid not null references public.placements(id) on delete cascade,
 student_id uuid not null references public.profiles(id), week integer not null check(week between 1 and 104),
 activity text not null, learning text, challenges text,
 status text not null default 'PENDING' check(status in ('PENDING','APPROVED','REJECTED')),
 feedback text, created_at timestamptz not null default now(), unique(placement_id,week)
);
create table if not exists public.attendance (
 id uuid primary key default gen_random_uuid(), placement_id uuid not null references public.placements(id) on delete cascade,
 student_id uuid not null references public.profiles(id), date date not null,
 hours numeric(4,1) not null check(hours > 0 and hours <= 24), note text,
 verified boolean not null default false, created_at timestamptz not null default now(),
 unique(placement_id,date)
);
create table if not exists public.assessments (
 id uuid primary key default gen_random_uuid(), placement_id uuid not null references public.placements(id) on delete cascade,
 supervisor_id uuid not null references public.profiles(id),
 score integer not null check(score between 0 and 100), comments text not null,
 created_at timestamptz not null default now(), unique(placement_id,supervisor_id)
);
create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 message text not null, is_read boolean not null default false,
 created_at timestamptz not null default now()
);
create or replace function public.my_role() returns text language sql stable security definer set search_path = '' as $$
 select role from public.profiles where id = (select auth.uid())
$$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
 select coalesce((select role = 'ADMIN' from public.profiles where id = (select auth.uid())), false)
$$;
create or replace function public.can_access_placement(pid uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select public.is_admin() or exists(select 1 from public.placements p where p.id=pid and
 (p.student_id=(select auth.uid()) or p.university_supervisor_id=(select auth.uid()) or p.industry_supervisor_id=(select auth.uid())))
$$;
create or replace function public.can_review_placement(pid uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select public.is_admin() or exists(select 1 from public.placements p where p.id=pid and
 (p.university_supervisor_id=(select auth.uid()) or p.industry_supervisor_id=(select auth.uid())))
$$;
create or replace function public.is_placement_student(pid uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.placements p where p.id=pid and p.student_id=(select auth.uid()))
$$;
create or replace function public.is_industry_supervisor(pid uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.placements p where p.id=pid and p.industry_supervisor_id=(select auth.uid()))
$$;
-- No public signup provisioned; admin creates Auth users via Supabase dashboard.
create or replace function public.create_own_profile() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,email,name,role)
 values(new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'name',''), 'STUDENT');
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.create_own_profile();

alter table public.profiles enable row level security;
alter table public.companies enable row level security;
alter table public.placements enable row level security;
alter table public.logbooks enable row level security;
alter table public.attendance enable row level security;
alter table public.assessments enable row level security;
alter table public.notifications enable row level security;
create policy "profiles read own and admin and placement participants" on public.profiles for select to authenticated using (
 id=(select auth.uid()) or public.is_admin() or exists(select 1 from public.placements p where
 (p.student_id=id or p.university_supervisor_id=id or p.industry_supervisor_id=id) and
 (p.student_id=(select auth.uid()) or p.university_supervisor_id=(select auth.uid()) or p.industry_supervisor_id=(select auth.uid())))
);
create policy "profiles admin update" on public.profiles for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "companies read" on public.companies for select to authenticated using(true);
create policy "companies admin insert" on public.companies for insert to authenticated with check(public.is_admin());
create policy "companies admin update" on public.companies for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "placements read assigned" on public.placements for select to authenticated using(public.can_access_placement(id));
create policy "placements admin insert" on public.placements for insert to authenticated with check(public.is_admin());
create policy "placements admin update" on public.placements for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "logbooks read assigned" on public.logbooks for select to authenticated using(public.can_access_placement(placement_id));
create policy "logbooks student insert" on public.logbooks for insert to authenticated with check(student_id=(select auth.uid()) and public.is_placement_student(placement_id) and status='PENDING' and feedback is null);
create policy "logbooks reviewer update" on public.logbooks for update to authenticated using(public.can_review_placement(placement_id)) with check(public.can_review_placement(placement_id));
create policy "attendance read assigned" on public.attendance for select to authenticated using(public.can_access_placement(placement_id));
create policy "attendance student insert" on public.attendance for insert to authenticated with check(student_id=(select auth.uid()) and public.is_placement_student(placement_id) and verified=false);
create policy "attendance verifier update" on public.attendance for update to authenticated using(public.is_admin() or public.is_industry_supervisor(placement_id)) with check(public.is_admin() or public.is_industry_supervisor(placement_id));
create policy "assessments read assigned" on public.assessments for select to authenticated using(public.can_access_placement(placement_id));
create policy "assessments supervisor insert" on public.assessments for insert to authenticated with check(supervisor_id=(select auth.uid()) and public.can_review_placement(placement_id) and public.my_role() in ('UNIVERSITY_SUPERVISOR','INDUSTRY_SUPERVISOR'));
create policy "notifications read own" on public.notifications for select to authenticated using(user_id=(select auth.uid()));
create policy "notifications mark own" on public.notifications for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
-- Lock sensitive fields for client-side updates. Role/status must not be self-editable.
revoke update on public.profiles from authenticated;
grant update(role,department,name) on public.profiles to authenticated;
revoke update on public.logbooks from authenticated;
grant update(status,feedback) on public.logbooks to authenticated;
revoke update on public.attendance from authenticated;
grant update(verified) on public.attendance to authenticated;
revoke update on public.notifications from authenticated;
grant update(is_read) on public.notifications to authenticated;
revoke update on public.placements from authenticated;
grant update(status) on public.placements to authenticated;
