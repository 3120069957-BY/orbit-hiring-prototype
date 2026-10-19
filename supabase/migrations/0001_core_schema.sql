-- Orbit MVP core schema.
-- Apply with Supabase CLI after creating a project and reviewing the policies.
create extension if not exists pgcrypto;

do $$ begin
  create type public.app_role as enum ('job_seeker', 'employer', 'platform_admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.company_verification_status as enum ('pending', 'verified', 'rejected', 'suspended');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.job_status as enum ('draft', 'pending_review', 'published', 'closed', 'rejected', 'suspended');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.application_status as enum ('submitted', 'reviewing', 'interviewing', 'rejected', 'hired', 'withdrawn');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.document_kind as enum ('resume', 'business_license');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  headline text not null default '',
  country text,
  school text,
  study_year text,
  field_of_study text,
  visibility text not null default 'private' check (visibility in ('private','employers')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Roles are assigned by trusted server/admin workflows. Never accept role claims from a client form.
create table if not exists public.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null,
  assigned_at timestamptz not null default now(),
  primary key (user_id, role)
);

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null,
  country text not null,
  registration_number text not null,
  verification_status public.company_verification_status not null default 'pending',
  verification_submitted_at timestamptz,
  verification_reviewed_at timestamptz,
  verification_note text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(country, registration_number)
);

create table if not exists public.company_members (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  member_role text not null default 'recruiter' check (member_role in ('owner','recruiter')),
  created_at timestamptz not null default now(),
  primary key (company_id, user_id)
);

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  kind public.document_kind not null,
  object_path text not null unique,
  original_name text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size > 0),
  created_at timestamptz not null default now(),
  check ((kind = 'business_license' and company_id is not null) or (kind = 'resume' and company_id is null))
);

create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  title text not null,
  description text not null default '',
  country text,
  location text,
  work_type text not null check (work_type in ('internship','part_time','full_time','contract')),
  industry text,
  salary_min numeric,
  salary_max numeric,
  currency text,
  status public.job_status not null default 'pending_review',
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (salary_min is null or salary_max is null or salary_min <= salary_max)
);

create table if not exists public.applications (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  candidate_id uuid not null references auth.users(id) on delete cascade,
  resume_document_id uuid references public.documents(id) on delete set null,
  status public.application_status not null default 'submitted',
  cover_message text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(job_id, candidate_id)
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  candidate_id uuid not null references auth.users(id) on delete cascade,
  recruiter_id uuid not null references auth.users(id) on delete cascade,
  application_id uuid references public.applications(id) on delete set null,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  unique(job_id, candidate_id, recruiter_id),
  check (candidate_id <> recruiter_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null default '',
  attachment_document_id uuid references public.documents(id) on delete set null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check (length(body) > 0 or attachment_document_id is not null)
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  target_user_id uuid references auth.users(id) on delete cascade,
  job_id uuid references public.jobs(id) on delete cascade,
  message_id uuid references public.messages(id) on delete cascade,
  reason text not null,
  details text not null default '',
  status text not null default 'open' check (status in ('open','investigating','resolved','dismissed')),
  resolution_note text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (num_nonnulls(target_user_id, job_id, message_id) = 1)
);

create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  admin_id uuid not null references auth.users(id),
  action text not null,
  target_type text not null,
  target_id text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists jobs_status_created_idx on public.jobs(status, created_at desc);
create index if not exists jobs_company_idx on public.jobs(company_id);
create index if not exists applications_candidate_idx on public.applications(candidate_id, created_at desc);
create index if not exists applications_job_idx on public.applications(job_id, created_at desc);
create index if not exists conversations_candidate_idx on public.conversations(candidate_id, last_message_at desc);
create index if not exists conversations_recruiter_idx on public.conversations(recruiter_id, last_message_at desc);
create index if not exists messages_conversation_idx on public.messages(conversation_id, created_at);
create index if not exists reports_status_idx on public.reports(status, created_at desc);

create or replace function public.has_role(required_role public.app_role)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid()) and ur.role = required_role
  );
$$;

create or replace function public.is_company_member(target_company uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.company_members cm
    where cm.company_id = target_company and cm.user_id = (select auth.uid())
  );
$$;

create or replace function public.is_conversation_member(target_conversation uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.conversations c
    where c.id = target_conversation
      and ((select auth.uid()) = c.candidate_id or (select auth.uid()) = c.recruiter_id)
  ) or public.has_role('platform_admin');
$$;

-- Keep company verification state controlled by platform admins, and re-review identity changes.
create or replace function public.guard_company_verification()
returns trigger language plpgsql set search_path = '' as $$
begin
  if coalesce(auth.uid() is null and current_user in ('postgres', 'service_role'), false)
     or public.has_role('platform_admin') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.verification_status <> 'pending' or new.verification_reviewed_at is not null then
      raise exception 'New companies must enter verification as pending';
    end if;
  else
    if new.verification_status is distinct from old.verification_status
       or new.verification_reviewed_at is distinct from old.verification_reviewed_at
       or new.verification_note is distinct from old.verification_note then
      raise exception 'Only platform admins can change verification decisions';
    end if;
    if new.legal_name is distinct from old.legal_name
       or new.country is distinct from old.country
       or new.registration_number is distinct from old.registration_number then
      new.verification_status := 'pending';
      new.verification_submitted_at := now();
      new.verification_reviewed_at := null;
      new.verification_note := null;
    end if;
  end if;
  return new;
end;
$$;
create trigger companies_guard_verification
before insert or update on public.companies
for each row execute function public.guard_company_verification();

-- Employers may close/reopen into review, but only an admin can publish, reject, or suspend a role.
create or replace function public.guard_job_moderation()
returns trigger language plpgsql set search_path = '' as $$
begin
  if coalesce(auth.uid() is null and current_user in ('postgres', 'service_role'), false)
     or public.has_role('platform_admin') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.status not in ('draft', 'pending_review') then
      raise exception 'New jobs must be submitted for review';
    end if;
  elsif new.status is distinct from old.status then
    if new.status not in ('draft', 'pending_review', 'closed') then
      raise exception 'Only platform admins can publish, reject, or suspend a job';
    end if;
    if old.status in ('published', 'rejected', 'suspended') and new.status = 'pending_review' then
      new.status := 'pending_review';
    end if;
  end if;
  return new;
end;
$$;
create trigger jobs_guard_moderation
before insert or update on public.jobs
for each row execute function public.guard_job_moderation();

create or replace function public.can_attach_resume(target_conversation uuid, target_document uuid, sender uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.conversations c
    join public.documents d on d.id = target_document
    where c.id = target_conversation and c.candidate_id = sender and sender = (select auth.uid())
      and d.owner_id = sender and d.kind = 'resume'
      and exists (select 1 from public.messages m where m.conversation_id = c.id and m.sender_id = c.candidate_id and m.attachment_document_id is null and length(m.body) > 0)
      and exists (select 1 from public.messages m where m.conversation_id = c.id and m.sender_id = c.recruiter_id)
  );
$$;
revoke all on function public.has_role(public.app_role) from public, anon;
revoke all on function public.is_company_member(uuid) from public, anon;
revoke all on function public.is_conversation_member(uuid) from public, anon;
revoke all on function public.can_attach_resume(uuid, uuid, uuid) from public, anon;
grant execute on function public.has_role(public.app_role), public.is_company_member(uuid), public.is_conversation_member(uuid), public.can_attach_resume(uuid, uuid, uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.companies enable row level security;
alter table public.company_members enable row level security;
alter table public.documents enable row level security;
alter table public.jobs enable row level security;
alter table public.applications enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.reports enable row level security;
alter table public.admin_audit_log enable row level security;

-- User-controlled profile fields only. Email/password remain in Supabase Auth.
create policy "Users read their own profile or visible candidate profiles" on public.profiles
for select to authenticated using (
  id = (select auth.uid())
  or public.has_role('platform_admin')
  or (visibility = 'employers' and public.has_role('employer'))
);
create policy "Users create their own profile" on public.profiles
for insert to authenticated with check (id = (select auth.uid()));
create policy "Users update their own profile" on public.profiles
for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "Users read their own assigned roles" on public.user_roles
for select to authenticated using (user_id = (select auth.uid()) or public.has_role('platform_admin'));

create policy "Verified companies are visible to signed in users" on public.companies
for select to authenticated using (
  verification_status = 'verified' or created_by = (select auth.uid())
  or public.is_company_member(id) or public.has_role('platform_admin')
);
create policy "Employers create a company for themselves" on public.companies
for insert to authenticated with check (created_by = (select auth.uid()) and public.has_role('employer') and verification_status = 'pending' and verification_reviewed_at is null);
create policy "Company members and admins update company data" on public.companies
for update to authenticated using (public.is_company_member(id) or public.has_role('platform_admin'))
with check (public.is_company_member(id) or public.has_role('platform_admin'));
create policy "Only admins delete company records" on public.companies
for delete to authenticated using (public.has_role('platform_admin'));

create policy "Members read company membership" on public.company_members
for select to authenticated using (user_id = (select auth.uid()) or public.is_company_member(company_id) or public.has_role('platform_admin'));
create policy "Company creator adds self as owner" on public.company_members
for insert to authenticated with check (
  user_id = (select auth.uid()) and member_role = 'owner'
  and exists (select 1 from public.companies c where c.id = company_id and c.created_by = (select auth.uid()))
);
create policy "Admins manage company membership" on public.company_members
for all to authenticated using (public.has_role('platform_admin')) with check (public.has_role('platform_admin'));

create policy "Owners and admins read document metadata" on public.documents
for select to authenticated using (
  owner_id = (select auth.uid()) or public.has_role('platform_admin')
  or (kind = 'business_license' and public.is_company_member(company_id))
  or (kind = 'resume' and exists (
    select 1 from public.applications a join public.jobs j on j.id = a.job_id
    where a.resume_document_id = id and a.candidate_id = owner_id and public.is_company_member(j.company_id)
  ))
);
create policy "Owners add resume or company license metadata" on public.documents
for insert to authenticated with check (
  owner_id = (select auth.uid()) and (
    (kind = 'resume' and company_id is null and public.has_role('job_seeker'))
    or (kind = 'business_license' and company_id is not null and public.has_role('employer') and public.is_company_member(company_id))
  )
);
create policy "Owners and admins delete document metadata" on public.documents
for delete to authenticated using (owner_id = (select auth.uid()) or public.has_role('platform_admin'));

create policy "Published verified jobs or own company jobs are visible" on public.jobs
for select to authenticated using (
  (status = 'published' and exists (select 1 from public.companies c where c.id = company_id and c.verification_status = 'verified'))
  or public.is_company_member(company_id) or public.has_role('platform_admin')
);
create policy "Verified company recruiters create jobs" on public.jobs
for insert to authenticated with check (
  created_by = (select auth.uid()) and public.has_role('employer') and public.is_company_member(company_id)
  and exists (select 1 from public.companies c where c.id = company_id and c.verification_status = 'verified')
);
create policy "Company recruiters and admins update jobs" on public.jobs
for update to authenticated using (public.is_company_member(company_id) or public.has_role('platform_admin'))
with check (public.is_company_member(company_id) or public.has_role('platform_admin'));
create policy "Admins delete jobs" on public.jobs
for delete to authenticated using (public.has_role('platform_admin'));

create policy "Candidates and hiring company members read applications" on public.applications
for select to authenticated using (
  candidate_id = (select auth.uid())
  or exists (select 1 from public.jobs j where j.id = job_id and public.is_company_member(j.company_id))
  or public.has_role('platform_admin')
);
create policy "Candidates apply to open published jobs" on public.applications
for insert to authenticated with check (
  candidate_id = (select auth.uid()) and public.has_role('job_seeker')
  and exists (select 1 from public.jobs j join public.companies c on c.id = j.company_id where j.id = job_id and j.status = 'published' and c.verification_status = 'verified')
  and (resume_document_id is null or exists (select 1 from public.documents d where d.id = resume_document_id and d.owner_id = (select auth.uid()) and d.kind = 'resume'))
);
create policy "Hiring team and admins update application status" on public.applications
for update to authenticated using (
  exists (select 1 from public.jobs j where j.id = job_id and public.is_company_member(j.company_id)) or public.has_role('platform_admin')
) with check (
  exists (select 1 from public.jobs j where j.id = job_id and public.is_company_member(j.company_id)) or public.has_role('platform_admin')
);
create policy "Candidates withdraw their own applications" on public.applications
for delete to authenticated using (candidate_id = (select auth.uid()));

create policy "Conversation participants read their threads" on public.conversations
for select to authenticated using (candidate_id = (select auth.uid()) or recruiter_id = (select auth.uid()) or public.has_role('platform_admin'));
create policy "Candidate or job owner starts a conversation" on public.conversations
for insert to authenticated with check (
  (candidate_id = (select auth.uid()) and public.has_role('job_seeker')
    and exists (select 1 from public.jobs j where j.id = job_id and j.status = 'published' and j.created_by = recruiter_id))
  or (recruiter_id = (select auth.uid()) and public.has_role('employer')
    and exists (select 1 from public.jobs j join public.profiles p on p.id = candidate_id where j.id = job_id and j.created_by = (select auth.uid()) and j.status = 'published' and p.visibility = 'employers'))
);
create policy "Participants update thread timestamps" on public.conversations
for update to authenticated using (candidate_id = (select auth.uid()) or recruiter_id = (select auth.uid()) or public.has_role('platform_admin'))
with check (candidate_id = (select auth.uid()) or recruiter_id = (select auth.uid()) or public.has_role('platform_admin'));

create policy "Conversation participants read messages" on public.messages
for select to authenticated using (public.is_conversation_member(conversation_id));
create policy "Participants send as themselves" on public.messages
for insert to authenticated with check (
  sender_id = (select auth.uid()) and public.is_conversation_member(conversation_id)
  and (attachment_document_id is null or public.can_attach_resume(conversation_id, attachment_document_id, (select auth.uid())))
);
create policy "Participants update message read state" on public.messages
for update to authenticated using (public.is_conversation_member(conversation_id))
with check (public.is_conversation_member(conversation_id));

create policy "Users submit reports" on public.reports
for insert to authenticated with check (
  reporter_id = (select auth.uid()) and (
    (target_user_id is not null and target_user_id <> (select auth.uid()))
    or job_id is not null or message_id is not null
  )
);
create policy "Reporters and admins read reports" on public.reports
for select to authenticated using (reporter_id = (select auth.uid()) or public.has_role('platform_admin'));
create policy "Admins manage reports" on public.reports
for update to authenticated using (public.has_role('platform_admin')) with check (public.has_role('platform_admin'));

create policy "Admins read audit events" on public.admin_audit_log
for select to authenticated using (public.has_role('platform_admin'));

-- Explicit grants complement RLS. Never expose service-role credentials in a client app.
revoke all on public.profiles, public.user_roles, public.companies, public.company_members,
  public.documents, public.jobs, public.applications, public.conversations, public.messages,
  public.reports, public.admin_audit_log from anon, authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select on public.user_roles to authenticated;
grant select, insert, update, delete on public.companies, public.company_members,
  public.documents, public.jobs, public.applications, public.conversations, public.messages, public.reports to authenticated;
grant select on public.admin_audit_log to authenticated;
revoke all on sequence public.admin_audit_log_id_seq from anon, authenticated;

-- Private bucket. Create this bucket in Supabase Storage with public=false before enabling uploads.
-- Document metadata must be created first; object_path is the exact storage object name.
create policy "Document owners upload private files" on storage.objects
for insert to authenticated with check (
  bucket_id = 'private-documents' and exists (
    select 1 from public.documents d where d.object_path = name and d.owner_id = (select auth.uid())
  )
);
create policy "Document owners and authorized reviewers download files" on storage.objects
for select to authenticated using (
  bucket_id = 'private-documents' and exists (
    select 1 from public.documents d where d.object_path = name and (
      d.owner_id = (select auth.uid()) or public.has_role('platform_admin')
      or (d.kind = 'business_license' and public.is_company_member(d.company_id))
      or (d.kind = 'resume' and exists (
        select 1 from public.applications a join public.jobs j on j.id = a.job_id
        where a.resume_document_id = d.id and public.is_company_member(j.company_id)
      ))
    )
  )
);
create policy "Document owners and admins delete private files" on storage.objects
for delete to authenticated using (
  bucket_id = 'private-documents' and exists (
    select 1 from public.documents d where d.object_path = name
      and (d.owner_id = (select auth.uid()) or public.has_role('platform_admin'))
  )
);
