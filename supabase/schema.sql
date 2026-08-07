-- Fasl üretim veritabanı şeması
create extension if not exists "pgcrypto";

create type public.story_status as enum ('draft', 'ongoing', 'completed');
create type public.story_visibility as enum ('public', 'unlisted', 'private');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_]{3,24}$'),
  display_name text not null check (char_length(display_name) between 1 and 60),
  bio text not null default '' check (char_length(bio) <= 300),
  avatar_url text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.stories (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 100),
  slug text not null,
  summary text not null default '' check (char_length(summary) <= 1200),
  genre text not null check (char_length(genre) between 1 and 40),
  tags text[] not null default '{}',
  cover_url text,
  status public.story_status not null default 'draft',
  visibility public.story_visibility not null default 'public',
  mature boolean not null default false,
  read_count bigint not null default 0 check (read_count >= 0),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (author_id, slug)
);

create table public.chapters (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  position integer not null check (position > 0),
  content text not null check (char_length(content) between 1 and 100000),
  is_published boolean not null default false,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (story_id, position)
);

create table public.story_likes (
  story_id uuid not null references public.stories(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (story_id, user_id)
);

create table public.library_items (
  story_id uuid not null references public.stories(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  last_chapter_id uuid references public.chapters(id) on delete set null,
  progress integer not null default 0 check (progress between 0 and 100),
  added_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (story_id, user_id)
);

create table public.chapter_comments (
  id uuid primary key default gen_random_uuid(),
  chapter_id uuid not null references public.chapters(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  message text not null check (char_length(message) between 1 and 800),
  parent_id uuid references public.chapter_comments(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followed_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  check (follower_id <> followed_id)
);

create index stories_discovery_idx on public.stories (visibility, published_at desc);
create index stories_author_idx on public.stories (author_id, updated_at desc);
create index stories_tags_idx on public.stories using gin (tags);
create index chapters_story_idx on public.chapters (story_id, position);
create index comments_chapter_idx on public.chapter_comments (chapter_id, created_at);
create index follows_followed_idx on public.follows (followed_id);

alter table public.profiles enable row level security;
alter table public.stories enable row level security;
alter table public.chapters enable row level security;
alter table public.story_likes enable row level security;
alter table public.library_items enable row level security;
alter table public.chapter_comments enable row level security;
alter table public.follows enable row level security;

create policy "Profiller okunabilir" on public.profiles for select using (true);
create policy "Kullanıcı profilini düzenleyebilir" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);
create policy "Yayımlanmış eserler okunabilir" on public.stories for select using (visibility = 'public' or author_id = auth.uid());
create policy "Yazar eser oluşturabilir" on public.stories for insert with check (author_id = auth.uid());
create policy "Yazar eserini düzenleyebilir" on public.stories for update using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy "Yazar eserini silebilir" on public.stories for delete using (author_id = auth.uid());
create policy "Yayımlanmış bölümler okunabilir" on public.chapters for select using (is_published or exists(select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid()));
create policy "Yazar bölüm oluşturabilir" on public.chapters for insert with check (exists(select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid()));
create policy "Yazar bölümü düzenleyebilir" on public.chapters for update using (exists(select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid()));
create policy "Yazar bölümü silebilir" on public.chapters for delete using (exists(select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid()));
create policy "Beğeniler okunabilir" on public.story_likes for select using (true);
create policy "Kullanıcı beğenebilir" on public.story_likes for insert with check (user_id = auth.uid());
create policy "Kullanıcı beğenisini kaldırabilir" on public.story_likes for delete using (user_id = auth.uid());
create policy "Kütüphane sahibine özeldir" on public.library_items for select using (user_id = auth.uid());
create policy "Kullanıcı kütüphanesine ekleyebilir" on public.library_items for insert with check (user_id = auth.uid());
create policy "Kullanıcı okuma ilerlemesini güncelleyebilir" on public.library_items for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Kullanıcı kütüphanesinden silebilir" on public.library_items for delete using (user_id = auth.uid());
create policy "Yorumlar okunabilir" on public.chapter_comments for select using (true);
create policy "Kullanıcı yorum yapabilir" on public.chapter_comments for insert with check (user_id = auth.uid());
create policy "Kullanıcı yorumunu düzenleyebilir" on public.chapter_comments for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Kullanıcı yorumunu silebilir" on public.chapter_comments for delete using (user_id = auth.uid());
create policy "Takipler okunabilir" on public.follows for select using (true);
create policy "Kullanıcı takip edebilir" on public.follows for insert with check (follower_id = auth.uid());
create policy "Kullanıcı takibi bırakabilir" on public.follows for delete using (follower_id = auth.uid());

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare base_username text;
begin
  base_username := lower(regexp_replace(coalesce(nullif(new.raw_user_meta_data->>'username',''), split_part(new.email,'@',1)), '[^a-z0-9_]', '', 'g'));
  if char_length(base_username) < 3 then base_username := 'okur'; end if;
  insert into public.profiles (id, username, display_name)
  values (new.id, left(base_username, 18) || '_' || substr(new.id::text, 1, 5), coalesce(nullif(new.raw_user_meta_data->>'display_name',''), 'Yeni anlatıcı'));
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();
