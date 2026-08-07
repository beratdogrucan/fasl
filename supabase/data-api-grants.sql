grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.stories, public.chapters, public.story_likes, public.chapter_comments, public.follows to anon, authenticated;
grant select, insert, update, delete on public.profiles, public.stories, public.chapters, public.story_likes, public.library_items, public.chapter_comments, public.follows to authenticated;
