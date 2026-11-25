-- 潮和國小 402 班｜差異化隨堂測驗「座號靜默分流」選用同步腳本
-- 適用於 math-quiz 與 chinese-quiz 共用之 Supabase 專案（不執行本腳本時，本機 localStorage 與靜態備援仍可 100% 正常運作）
-- 執行方式：貼到 Supabase Dashboard -> SQL Editor 執行一次即可（可重複執行，具冪等性）。
-- 隱私設計：本表僅儲存 16 碼匿名雜湊 token，絕不儲存學生姓名、班級或明文座號。

CREATE TABLE IF NOT EXISTS public.support_roster (
  token text PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.support_roster ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "support_roster_anon_select" ON public.support_roster;
CREATE POLICY "support_roster_anon_select"
  ON public.support_roster
  FOR SELECT
  TO anon, authenticated
  USING (true);

REVOKE INSERT, UPDATE, DELETE ON public.support_roster FROM anon, authenticated;
GRANT SELECT ON public.support_roster TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.teacher_set_support_tokens(
  pw text,
  p_tokens text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cleaned_tokens text[];
  inserted_count integer := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.teacher_config t
    WHERE t.pw = teacher_set_support_tokens.pw
  ) THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  SELECT COALESCE(
    ARRAY(
      SELECT DISTINCT lower(trim(tok))
      FROM unnest(COALESCE(p_tokens, ARRAY[]::text[])) AS tok
      WHERE trim(tok) <> ''
        AND length(trim(tok)) <= 64
        AND lower(trim(tok)) ~ '^[0-9a-f]+$'
    ),
    ARRAY[]::text[]
  )
  INTO cleaned_tokens;

  DELETE FROM public.support_roster;

  IF array_length(cleaned_tokens, 1) IS NOT NULL THEN
    INSERT INTO public.support_roster (token)
    SELECT tok
    FROM unnest(cleaned_tokens) AS tok
    ON CONFLICT (token) DO NOTHING;

    GET DIAGNOSTICS inserted_count = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'count', inserted_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.teacher_set_support_tokens(text, text[]) TO anon, authenticated;
