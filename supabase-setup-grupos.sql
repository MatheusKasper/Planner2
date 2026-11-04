-- Rode DEPOIS do supabase-setup.sql. Cole tudo no SQL Editor → Run.

-- Perfis (nome, foto e resumo de progresso compartilhado com o grupo)
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  avatar text not null default '',
  stats jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 6)),
  owner uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  text text not null default '',
  photo text,
  created_at timestamptz not null default now()
);

-- Funções auxiliares (evitam recursão nas regras de segurança)
create or replace function public.my_groups() returns setof uuid
  language sql security definer set search_path = public stable
  as $$ select group_id from public.group_members where user_id = auth.uid() $$;

create or replace function public.is_member(g uuid) returns boolean
  language sql security definer set search_path = public stable
  as $$ select exists (select 1 from public.group_members where group_id = g and user_id = auth.uid()) $$;

-- Criar grupo (quem cria já entra como membro)
create or replace function public.create_group(p_name text) returns public.groups
  language plpgsql security definer set search_path = public as $$
declare g public.groups;
begin
  if auth.uid() is null then raise exception 'Entre na sua conta primeiro.'; end if;
  insert into public.groups (name, owner) values (left(trim(p_name), 60), auth.uid()) returning * into g;
  insert into public.group_members (group_id, user_id) values (g.id, auth.uid());
  return g;
end $$;

-- Entrar por código (limite de 8 pessoas por grupo)
create or replace function public.join_group(p_code text) returns public.groups
  language plpgsql security definer set search_path = public as $$
declare g public.groups; n int;
begin
  if auth.uid() is null then raise exception 'Entre na sua conta primeiro.'; end if;
  select * into g from public.groups where code = upper(trim(p_code));
  if not found then raise exception 'Código de grupo não encontrado.'; end if;
  if exists (select 1 from public.group_members where group_id = g.id and user_id = auth.uid()) then return g; end if;
  select count(*) into n from public.group_members where group_id = g.id;
  if n >= 8 then raise exception 'Este grupo já tem 8 pessoas (limite máximo).'; end if;
  insert into public.group_members (group_id, user_id) values (g.id, auth.uid());
  return g;
end $$;

grant execute on function public.create_group(text) to authenticated;
grant execute on function public.join_group(text) to authenticated;

-- Regras de segurança
alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.posts enable row level security;

create policy "profiles_select" on public.profiles for select
  using (user_id = auth.uid() or user_id in (select user_id from public.group_members where group_id in (select public.my_groups())));
create policy "profiles_insert" on public.profiles for insert with check (user_id = auth.uid());
create policy "profiles_update" on public.profiles for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "groups_select" on public.groups for select using (public.is_member(id));
create policy "groups_delete" on public.groups for delete using (owner = auth.uid());

create policy "members_select" on public.group_members for select using (group_id in (select public.my_groups()));
create policy "members_leave" on public.group_members for delete using (user_id = auth.uid());

create policy "posts_select" on public.posts for select using (public.is_member(group_id));
create policy "posts_insert" on public.posts for insert with check (public.is_member(group_id) and user_id = auth.uid());
create policy "posts_delete" on public.posts for delete using (user_id = auth.uid());

-- Tempo real
alter publication supabase_realtime add table public.posts;
alter publication supabase_realtime add table public.group_members;

-- Fotos do mural (bucket privado; só membros do grupo acessam a pasta do grupo)
insert into storage.buckets (id, name, public) values ('group-photos', 'group-photos', false) on conflict (id) do nothing;

create policy "gphotos_select" on storage.objects for select to authenticated
  using (bucket_id = 'group-photos' and public.is_member(((storage.foldername(name))[1])::uuid));
create policy "gphotos_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'group-photos' and public.is_member(((storage.foldername(name))[1])::uuid));
create policy "gphotos_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'group-photos' and public.is_member(((storage.foldername(name))[1])::uuid));
