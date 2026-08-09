-- Fasl kapsamlı platform özellikleri
alter table public.profiles add column if not exists avatar_url text;
alter table public.stories add column if not exists trailer_url text;
alter table public.stories add column if not exists scheduled_at timestamptz;
alter table public.chapters add column if not exists scheduled_at timestamptz;
alter table public.chapter_comments add column if not exists paragraph_index integer check (paragraph_index is null or paragraph_index >= 0);
alter table public.library_items add column if not exists shelf text not null default 'reading'
  check (shelf in ('later','reading','completed'));

create table if not exists public.author_announcements (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  message text not null check (char_length(message) between 1 and 500),
  created_at timestamptz not null default now()
);

create table if not exists public.contests (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  theme text not null default '',
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.contest_entries (
  contest_id uuid not null references public.contests(id) on delete cascade,
  story_id uuid not null references public.stories(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (contest_id, story_id)
);

create table if not exists public.support_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  category text not null check (category in ('support','account_deletion','data_request','copyright')),
  subject text not null check (char_length(subject) between 3 and 120),
  message text not null check (char_length(message) between 10 and 2000),
  status text not null default 'open' check (status in ('open','in_progress','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.email_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  new_chapter boolean not null default true,
  new_comment boolean not null default true,
  new_follower boolean not null default true,
  product_news boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.email_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  subject text not null,
  body text not null,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.author_announcements enable row level security;
alter table public.contests enable row level security;
alter table public.contest_entries enable row level security;
alter table public.support_requests enable row level security;
alter table public.email_preferences enable row level security;
alter table public.email_outbox enable row level security;

grant select on public.author_announcements, public.contests, public.contest_entries to anon, authenticated;
grant insert, update, delete on public.author_announcements, public.contest_entries to authenticated;
grant insert, update, delete on public.contests to authenticated;
grant select, insert, update on public.support_requests to authenticated;
grant select, insert, update on public.email_preferences to authenticated;

drop policy if exists "Duyurular okunabilir" on public.author_announcements;
create policy "Duyurular okunabilir" on public.author_announcements for select using (true);
drop policy if exists "Yazar duyuru yonetebilir" on public.author_announcements;
create policy "Yazar duyuru yonetebilir" on public.author_announcements for all using (author_id=auth.uid()) with check (author_id=auth.uid());
drop policy if exists "Yarismalar okunabilir" on public.contests;
create policy "Yarismalar okunabilir" on public.contests for select using (true);
drop policy if exists "Yarisma katilimlari okunabilir" on public.contest_entries;
create policy "Yarisma katilimlari okunabilir" on public.contest_entries for select using (true);
drop policy if exists "Kullanici yarismaya katilabilir" on public.contest_entries;
create policy "Kullanici yarismaya katilabilir" on public.contest_entries for insert with check (user_id=auth.uid());
drop policy if exists "Kullanici katilimini silebilir" on public.contest_entries;
create policy "Kullanici katilimini silebilir" on public.contest_entries for delete using (user_id=auth.uid());
drop policy if exists "Kullanici destek talebi acabilir" on public.support_requests;
create policy "Kullanici destek talebi acabilir" on public.support_requests for insert with check (user_id=auth.uid());
drop policy if exists "Kullanici taleplerini gorebilir" on public.support_requests;
create policy "Kullanici taleplerini gorebilir" on public.support_requests for select using (user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin));
drop policy if exists "Kullanici eposta tercihini gorebilir" on public.email_preferences;
create policy "Kullanici eposta tercihini gorebilir" on public.email_preferences for select using (user_id=auth.uid());
drop policy if exists "Kullanici eposta tercihini ekleyebilir" on public.email_preferences;
create policy "Kullanici eposta tercihini ekleyebilir" on public.email_preferences for insert with check (user_id=auth.uid());
drop policy if exists "Kullanici eposta tercihini guncelleyebilir" on public.email_preferences;
create policy "Kullanici eposta tercihini guncelleyebilir" on public.email_preferences for update using (user_id=auth.uid()) with check (user_id=auth.uid());

-- Yönetici yarışma ve destek taleplerini yönetebilir.
drop policy if exists "Yonetici yarismalari yonetebilir" on public.contests;
create policy "Yonetici yarismalari yonetebilir" on public.contests for all using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin)) with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin));
drop policy if exists "Yonetici destek taleplerini guncelleyebilir" on public.support_requests;
create policy "Yonetici destek taleplerini guncelleyebilir" on public.support_requests for update using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin));

create or replace function public.notify_author_announcement()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.notifications(user_id,kind,title,body)
  select follower_id,'system','Takip ettiğin yazardan yeni duyuru',left(new.message,500)
  from public.follows where followed_id=new.author_id;
  return new;
end; $$;
drop trigger if exists on_author_announcement on public.author_announcements;
create trigger on_author_announcement after insert on public.author_announcements
for each row execute procedure public.notify_author_announcement();

create or replace function public.queue_notification_email()
returns trigger language plpgsql security definer set search_path=public as $$
declare prefs public.email_preferences%rowtype;
begin
  select * into prefs from public.email_preferences where user_id=new.user_id;
  if (new.kind='new_chapter' and coalesce(prefs.new_chapter,true)) or (new.kind='system' and coalesce(prefs.product_news,false)) then
    insert into public.email_outbox(user_id,kind,subject,body) values(new.user_id,new.kind,new.title,new.body);
  end if;
  return new;
end; $$;
drop trigger if exists on_notification_queue_email on public.notifications;
create trigger on_notification_queue_email after insert on public.notifications
for each row execute procedure public.queue_notification_email();

create or replace function public.publish_due_content()
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.stories set visibility='public',status='ongoing',published_at=coalesce(published_at,now()),scheduled_at=null
  where scheduled_at is not null and scheduled_at<=now();
  update public.chapters set is_published=true,published_at=coalesce(published_at,now()),scheduled_at=null
  where scheduled_at is not null and scheduled_at<=now();
end; $$;
grant execute on function public.publish_due_content() to anon, authenticated;

create or replace function public.notify_new_chapter()
returns trigger language plpgsql security definer set search_path=public as $$
declare story_row public.stories%rowtype;
begin
  if not new.is_published or (tg_op='UPDATE' and old.is_published) then return new; end if;
  select * into story_row from public.stories where id=new.story_id;
  insert into public.notifications(user_id,kind,title,body,story_id,chapter_id)
  select distinct recipient,'new_chapter',story_row.title || ' — yeni fasıl',new.title || ' yayımlandı.',new.story_id,new.id
  from (
    select follower_id recipient from public.follows where followed_id=story_row.author_id
    union
    select user_id recipient from public.library_items where story_id=new.story_id
  ) audience where recipient<>story_row.author_id;
  return new;
end; $$;
drop trigger if exists on_published_chapter_notify on public.chapters;
create trigger on_published_chapter_notify after insert or update of is_published on public.chapters
for each row execute procedure public.notify_new_chapter();
