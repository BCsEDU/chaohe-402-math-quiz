-- 選用升級腳本（math-quiz 已內建零 SQL 備援機制，不執行此腳本也可 100% 正常運作）
-- 若要啟用「跨裝置同日限考一次鎖定」與 submissions 表原生的 bonus_points / retry_* 欄位，
-- 請到 Supabase Dashboard -> SQL Editor 貼上並執行一次即可（完全相容既有 chinese-quiz 與 xueli-quiz）。

ALTER TABLE public.submissions
  ADD COLUMN IF NOT EXISTS bonus_points integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS retry_answers integer[],
  ADD COLUMN IF NOT EXISTS retry_passed boolean,
  ADD COLUMN IF NOT EXISTS retry_at timestamptz;

CREATE OR REPLACE FUNCTION public.teacher_get_submissions(pw text)
RETURNS SETOF public.submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.teacher_config t WHERE t.pw = teacher_get_submissions.pw) THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;
  RETURN QUERY SELECT * FROM public.submissions WHERE NOT COALESCE(is_deleted, false) ORDER BY created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_student_exam_status(
  p_exam_id text,
  p_class text,
  p_seat integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  taipei_today date := (now() AT TIME ZONE 'Asia/Taipei')::date;
  rec public.submissions%ROWTYPE;
BEGIN
  SELECT *
  INTO rec
  FROM public.submissions s
  WHERE s.exam_id = p_exam_id
    AND s.class = p_class
    AND s.seat = p_seat
    AND NOT COALESCE(s.is_deleted, false)
    AND (s.created_at AT TIME ZONE 'Asia/Taipei')::date = taipei_today
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  RETURN jsonb_build_object(
    'found', true,
    'id', rec.id,
    'client_id', rec.client_id,
    'name', rec.name,
    'score', rec.score,
    'total', rec.total,
    'answers', rec.answers,
    'bonus_points', rec.bonus_points,
    'retry_passed', rec.retry_passed,
    'retry_answers', rec.retry_answers,
    'created_at', rec.created_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_exam_retry(
  p_client_id text,
  p_retry_answers integer[],
  p_retry_passed boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated_id bigint;
  new_bonus integer;
BEGIN
  new_bonus := CASE WHEN p_retry_passed THEN 10 ELSE 0 END;

  UPDATE public.submissions
  SET retry_answers = p_retry_answers,
      retry_passed = p_retry_passed,
      bonus_points = new_bonus,
      retry_at = now()
  WHERE client_id = p_client_id
    AND NOT COALESCE(is_deleted, false)
    AND retry_passed IS NULL
    AND score < total
  RETURNING id INTO updated_id;

  IF updated_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_retried_or_not_found');
  END IF;

  RETURN jsonb_build_object('ok', true, 'id', updated_id, 'bonus_points', new_bonus);
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_student_exam_status(text, text, integer) TO anon;
GRANT EXECUTE ON FUNCTION public.submit_exam_retry(text, integer[], boolean) TO anon;
