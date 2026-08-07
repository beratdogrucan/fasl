-- Fasl bildirim, itiraz ve yönetici özellikleri
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('new_chapter', 'system')),
  title text not null check (char_length(title) between 1 and 160),
  body text not null default '' check (char_length(body) <= 500),
  story_id uuid references public.stories(id) on delete cascade,
  chapter_id uuid references public.chapters(id) on delete cascade,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('comment', 'story')),
  target_id uuid not null,
  reason text not null check (char_length(reason) between 3 and 800),
  status text not null default 'open' check (status in ('open', 'reviewed', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);
create index if not exists reports_status_idx on public.reports (status, created_at desc);
alter table public.notifications enable row level security;
alter table public.reports enable row level security;

grant select, insert, update, delete on public.notifications, public.reports to authenticated;

drop policy if exists "Kullanıcı bildirimlerini okuyabilir" on public.notifications;
create policy "Kullanıcı bildirimlerini okuyabilir" on public.notifications for select using (user_id = auth.uid());
drop policy if exists "Yönetici bildirimleri okuyabilir" on public.notifications;
create policy "Yönetici bildirimleri okuyabilir" on public.notifications for select using (
  exists(select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
);
drop policy if exists "Kullanıcı bildirimlerini güncelleyebilir" on public.notifications;
create policy "Kullanıcı bildirimlerini güncelleyebilir" on public.notifications for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "Kullanıcı bildirimlerini silebilir" on public.notifications;
create policy "Kullanıcı bildirimlerini silebilir" on public.notifications for delete using (user_id = auth.uid());

drop policy if exists "Kullanıcı itiraz oluşturabilir" on public.reports;
create policy "Kullanıcı itiraz oluşturabilir" on public.reports for insert with check (reporter_id = auth.uid());
drop policy if exists "Kullanıcı itirazını görebilir" on public.reports;
create policy "Kullanıcı itirazını görebilir" on public.reports for select using (
  reporter_id = auth.uid() or exists(select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
);
drop policy if exists "Yönetici itirazı güncelleyebilir" on public.reports;
create policy "Yönetici itirazı güncelleyebilir" on public.reports for update using (
  exists(select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
) with check (exists(select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

drop policy if exists "Yönetici yorumu silebilir" on public.chapter_comments;
create policy "Yönetici yorumu silebilir" on public.chapter_comments for delete using (
  exists(select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
);

create or replace function public.notify_new_chapter()
returns trigger language plpgsql security definer set search_path = public as $$
declare story_row public.stories%rowtype;
begin
  if not new.is_published then return new; end if;
  select * into story_row from public.stories where id = new.story_id;
  insert into public.notifications (user_id, kind, title, body, story_id, chapter_id)
  select distinct recipient, 'new_chapter', story_row.title || ' — yeni fasıl', new.title || ' yayımlandı.', new.story_id, new.id
  from (
    select follower_id as recipient from public.follows where followed_id = story_row.author_id
    union
    select user_id as recipient from public.library_items where story_id = new.story_id
  ) audience
  where recipient <> story_row.author_id;
  return new;
end;
$$;

drop trigger if exists on_published_chapter_notify on public.chapters;
create trigger on_published_chapter_notify after insert on public.chapters
for each row execute procedure public.notify_new_chapter();
