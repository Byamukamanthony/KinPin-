-- SUPABASE DDL SCHEMA & INITIAL DATA SEED SCRIPT
-- For Kingpin Campus Applet Database Environment

-- Enable PG Extensions (UUID generate functions)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

----------------------------------------------------
-- 1. PROFILES TABLE (Associated with auth.users)
----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    display_name TEXT,
    photo_url TEXT,
    balance NUMERIC DEFAULT 0,
    referral_code TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW())
);

-- Row Level Security (RLS) Settings
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read access to profiles" 
ON public.profiles FOR SELECT USING (true);

CREATE POLICY "Allow individual profile update" 
ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Trigger to automatically create a custom Profile entry whenever a user registers with Supabase Auth
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, display_name, photo_url, balance, referral_code)
    VALUES (
        new.id,
        new.email,
        coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)),
        coalesce(new.raw_user_meta_data->>'avatar_url', ''),
        0,
        'KPIN-' || upper(substring(new.id::text, 1, 5))
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


----------------------------------------------------
-- 2. DEALS TABLE (Campus peer-discount offerings)
----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.deals (
    id VARCHAR(255) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    discount VARCHAR(100),
    price_string VARCHAR(100),
    original_price_string VARCHAR(100),
    description TEXT,
    image TEXT,
    location VARCHAR(255),
    is_custom BOOLEAN DEFAULT FALSE,
    claims_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW())
);

ALTER TABLE public.deals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read access to deals" ON public.deals FOR SELECT USING (true);
CREATE POLICY "Allow authenticated users to insert deals" ON public.deals FOR INSERT WITH CHECK (auth.role() = 'authenticated');


----------------------------------------------------
-- 3. DEAL CLAIMS TABLE (Tracks claimed student discounts)
----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.deal_claims (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    deal_id VARCHAR(255) REFERENCES public.deals(id) ON DELETE CASCADE,
    claimed_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()),
    CONSTRAINT unique_user_deal_claim UNIQUE (user_id, deal_id)
);

ALTER TABLE public.deal_claims ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow user to view their own claims" ON public.deal_claims FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Allow user to submit their own claim" ON public.deal_claims FOR INSERT WITH CHECK (auth.uid() = user_id);


----------------------------------------------------
-- 4. POSTS TABLE (Campus Gossip Feed Core)
----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.posts (
    id VARCHAR(255) PRIMARY KEY,
    username VARCHAR(100) NOT NULL,
    avatar TEXT,
    category VARCHAR(100) NOT NULL,
    tag VARCHAR(50), -- 'TRENDING', 'HOT DROP', 'ALERT', 'ANNOUNCEMENT', 'GOSSIP'
    text TEXT,
    image TEXT,
    likes_count INTEGER DEFAULT 0,
    comments_count INTEGER DEFAULT 0,
    is_hustle_offer BOOLEAN DEFAULT FALSE,
    product_title VARCHAR(255),
    product_price VARCHAR(100),
    product_desc TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW())
);

ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read access to gossip posts" ON public.posts FOR SELECT USING (true);
CREATE POLICY "Allow authenticated users to upload posts" ON public.posts FOR INSERT WITH CHECK (auth.role() = 'authenticated');


----------------------------------------------------
-- 5. POST LIKES TABLE (Likes/Flames tracking table)
----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.post_likes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    post_id VARCHAR(255) REFERENCES public.posts(id) ON DELETE CASCADE,
    liked_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()),
    CONSTRAINT unique_user_post_like UNIQUE (user_id, post_id)
);

ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read access to post likes" ON public.post_likes FOR SELECT USING (true);
CREATE POLICY "Allow user to toggle their own like" ON public.post_likes FOR ALL USING (auth.uid() = user_id);


----------------------------------------------------
-- 6. POST COMMENTS TABLE (Comments under gossip leaks)
----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.post_comments (
    id VARCHAR(255) PRIMARY KEY,
    post_id VARCHAR(255) REFERENCES public.posts(id) ON DELETE CASCADE,
    username VARCHAR(100) NOT NULL,
    text TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW())
);

ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read comments" ON public.post_comments FOR SELECT USING (true);
CREATE POLICY "Allow authenticated write comment" ON public.post_comments FOR INSERT WITH CHECK (auth.role() = 'authenticated');


----------------------------------------------------
-- 7. EVENTS TABLE (University Parties, Sessions, Events)
----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.events (
    id VARCHAR(255) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    location VARCHAR(255),
    date VARCHAR(100),
    time VARCHAR(100),
    image TEXT,
    is_hottest BOOLEAN DEFAULT FALSE,
    is_verified BOOLEAN DEFAULT FALSE,
    verified_label VARCHAR(255),
    price_string VARCHAR(100),
    price_sub_label VARCHAR(100),
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'pending'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW())
);

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read access to events" ON public.events FOR SELECT USING (true);
CREATE POLICY "Allow logged users to create events" ON public.events FOR INSERT WITH CHECK (auth.role() = 'authenticated');


----------------------------------------------------
-- 8. EVENT RSVPS TABLE (Tracks campus event tickets and RSVP list)
----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_rsvps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    event_id VARCHAR(255) REFERENCES public.events(id) ON DELETE CASCADE,
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()),
    CONSTRAINT unique_user_event_rsvp UNIQUE (user_id, event_id)
);

ALTER TABLE public.event_rsvps ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow user to view their own event RSVPs" ON public.event_rsvps FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Allow user to submit RSVP" ON public.event_rsvps FOR INSERT WITH CHECK (auth.uid() = user_id);


----------------------------------------------------
-- 9. PRODUCTS TABLE (Peer-to-peer Trading Marketplace Items)
----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.products (
    id VARCHAR(255) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    price_string VARCHAR(100),
    price_number NUMERIC,
    image TEXT,
    location VARCHAR(255),
    category VARCHAR(100), -- 'Tech', 'Fashion', 'Services', 'Notes'
    is_verified BOOLEAN DEFAULT FALSE,
    whatsapp_number VARCHAR(50),
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'pending'
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW())
);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read products" ON public.products FOR SELECT USING (true);
CREATE POLICY "Allow user to post marketplace selling products" ON public.products FOR INSERT WITH CHECK (auth.role() = 'authenticated');


----------------------------------------------------
-- 10. ACTIVITIES TABLE (Commissions/Payout Transaction History logs)
----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.activities (
    id VARCHAR(255) PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    amount NUMERIC NOT NULL,
    direction VARCHAR(50) NOT NULL, -- 'in', 'out'
    date_str VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW())
);

ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow user to read their own financial logs" ON public.activities FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Allow server-side ledger insert" ON public.activities FOR INSERT WITH CHECK (auth.uid() = user_id);


----------------------------------------------------
-- 11. COMMUNITIES TABLE (Campus Circles social clusters)
----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.communities (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    description TEXT,
    created_by VARCHAR(255),
    members_count INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW())
);

ALTER TABLE public.communities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read communities" ON public.communities FOR SELECT USING (true);
CREATE POLICY "Allow registered user to draft custom circle" ON public.communities FOR INSERT WITH CHECK (auth.role() = 'authenticated');


--------------------------------------------------------------------------------------------------------
-- END OF DDL SCHEMA DEFINITIONS
--------------------------------------------------------------------------------------------------------
