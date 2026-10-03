-- Emoji presentation is independent of OAuth profile images.

alter table public.profiles add column avatar_emoji text;
alter table public.profiles add constraint profiles_avatar_emoji_length
  check (avatar_emoji is null or char_length(avatar_emoji) between 1 and 32);
comment on column public.profiles.avatar_emoji is
  'Optional Unicode emoji avatar; null retains the default client presentation.';

grant update (avatar_emoji) on public.profiles to authenticated;

CREATE OR REPLACE FUNCTION private.get_account_overview() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
declare
  v_user_id uuid := public.ensure_profile();
  v_profile jsonb;
  v_apps jsonb;
begin
  select jsonb_build_object(
    'id', p.id,
    'email', p.email,
    'displayName', p.display_name,
    'avatarUrl', p.avatar_url,
    'avatarEmoji', p.avatar_emoji,
    'revenueCatAppUserId', p.revenuecat_app_user_id,
    'appleAppAccountToken', p.apple_app_account_token,
    'pomodoistIsPro', p.pomodoist_is_pro
  )
  into v_profile
  from public.profiles p
  where p.id = v_user_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'displayName', a.display_name,
        'installed', exists (
          select 1
          from public.user_app_installs i
          where i.user_id = v_user_id
            and i.app_id = a.id
        ),
        'entitlements', coalesce((
          select jsonb_agg(jsonb_build_object(
            'appId', e.app_id,
            'entitlementId', e.entitlement_id,
            'status', e.status,
            'purchaseType', e.purchase_type,
            'source', e.source,
            'productId', e.product_id,
            'store', e.store,
            'validUntil', e.valid_until,
            'renewsAt', e.renews_at
          ) order by e.updated_at desc)
          from public.user_entitlements e
          where e.user_id = v_user_id
            and e.app_id = a.id
        ), '[]'::jsonb),
        'usage', coalesce((
          select jsonb_agg(jsonb_build_object(
            'appId', u.app_id,
            'quotaKey', u.quota_key,
            'used', u.used,
            'limit', u.limit_value,
            'unit', u.unit,
            'periodEnd', u.period_end
          ) order by u.period_end desc)
          from public.usage_periods u
          where u.user_id = v_user_id
            and u.app_id = a.id
            and u.period_end > timezone('utc', now())
        ), '[]'::jsonb),
        'purchaseBinding', null,
        'storage', null
      )
      order by case when a.id = 'pomodoist' then 1 else 2 end, a.id
    ),
    '[]'::jsonb
  )
  into v_apps
  from public.apps a;

  return jsonb_build_object(
    'profile', v_profile,
    'apps', v_apps,
    'generatedAt', timezone('utc', now())
  );
end;
$$;


-- Preserve the existing authenticated-only RPC grants and ownership.
notify pgrst, 'reload schema';
