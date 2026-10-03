-- Forma del trofeo disegnata dall'app quando non è stata caricata un'immagine.
alter table trophies
  add column if not exists shape text not null default 'coppa'
  check (shape in ('coppa', 'targa', 'medaglia', 'scudetto', 'stella'));
