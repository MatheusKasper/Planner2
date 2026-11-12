-- Rode DEPOIS do supabase-setup-lote1.sql. Cole tudo no SQL Editor → Run.

-- 1) Comentários nas mensagens (um comentário é uma mensagem com "parent_id")
alter table public.posts add column if not exists parent_id uuid references public.posts(id) on delete cascade;

-- 2) Reações no mural
create table if not exists public.post_reactions (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null,
  group_id uuid not null references public.groups(id) on delete cascade,
  primary key (post_id, user_id, emoji)
);
alter table public.post_reactions enable row level security;
create policy "reactions_select" on public.post_reactions for select using (public.is_member(group_id));
create policy "reactions_insert" on public.post_reactions for insert
  with check (user_id = auth.uid() and public.is_member(group_id));
create policy "reactions_delete" on public.post_reactions for delete using (user_id = auth.uid());

-- 3) Meta coletiva do grupo (só o dono define)
create table if not exists public.group_goals (
  group_id uuid primary key references public.groups(id) on delete cascade,
  title text not null,
  target int not null check (target > 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.group_goals enable row level security;
create policy "ggoals_select" on public.group_goals for select using (public.is_member(group_id));
create policy "ggoals_insert" on public.group_goals for insert
  with check (exists (select 1 from public.groups g where g.id = group_goals.group_id and g.owner = auth.uid()));
create policy "ggoals_update" on public.group_goals for update
  using (exists (select 1 from public.groups g where g.id = group_goals.group_id and g.owner = auth.uid()))
  with check (exists (select 1 from public.groups g where g.id = group_goals.group_id and g.owner = auth.uid()));
create policy "ggoals_delete" on public.group_goals for delete
  using (exists (select 1 from public.groups g where g.id = group_goals.group_id and g.owner = auth.uid()));

-- 4) Duelos 1 contra 1
create table if not exists public.duels (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  challenger uuid not null references auth.users(id) on delete cascade,
  opponent uuid not null references auth.users(id) on delete cascade,
  stake int not null default 50 check (stake between 10 and 500),
  days int not null default 7 check (days between 1 and 30),
  status text not null default 'pendente' check (status in ('pendente','ativo','recusado','fim')),
  c_base int not null default 0,
  o_base int not null default 0,
  start_day date,
  end_day date,
  winner uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (challenger <> opponent)
);
alter table public.duels enable row level security;
create policy "duels_select" on public.duels for select using (public.is_member(group_id));
create policy "duels_insert" on public.duels for insert
  with check (challenger = auth.uid() and public.is_member(group_id)
    and exists (select 1 from public.group_members m where m.group_id = duels.group_id and m.user_id = duels.opponent));
create policy "duels_update" on public.duels for update
  using (auth.uid() in (challenger, opponent)) with check (auth.uid() in (challenger, opponent));
create policy "duels_delete" on public.duels for delete using (challenger = auth.uid());

-- 5) Backups automáticos semanais (cada pessoa só vê os seus)
create table if not exists public.planner_backups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  data jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.planner_backups enable row level security;
create policy "backups_select" on public.planner_backups for select using (user_id = auth.uid());
create policy "backups_insert" on public.planner_backups for insert with check (user_id = auth.uid());
create policy "backups_delete" on public.planner_backups for delete using (user_id = auth.uid());

-- 6) Tempo real
alter publication supabase_realtime add table public.duels, public.group_goals, public.post_reactions;
