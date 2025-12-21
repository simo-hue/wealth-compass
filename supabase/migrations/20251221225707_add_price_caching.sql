-- Add caching columns to assets table
ALTER TABLE public.assets 
ADD COLUMN IF NOT EXISTS current_price numeric DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_price_update timestamptz;

-- Comment on columns
COMMENT ON COLUMN public.assets.current_price IS 'Cached last known price per unit';
COMMENT ON COLUMN public.assets.last_price_update IS 'Timestamp of the last successful price fetch';
