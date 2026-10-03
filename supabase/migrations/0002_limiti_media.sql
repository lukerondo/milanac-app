-- Limiti di sicurezza sui file caricati (protegge il piano gratuito da 1 GB).
update storage.buckets
set file_size_limit = 15 * 1024 * 1024,                       -- 15 MB per file
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime']
where id = 'match-media';

update storage.buckets
set file_size_limit = 5 * 1024 * 1024,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
where id in ('avatars', 'trophies');
