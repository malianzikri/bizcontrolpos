import { createClient } from 'npm:@supabase/supabase-js@^2'
import { corsHeaders } from 'npm:@supabase/supabase-js@^2/cors'

const responseHeaders = {
  ...corsHeaders,
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...responseHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  })
}

function emailKey(value: unknown) {
  return String(value || '').trim().toLowerCase()
}

function configuredSystemAdmins() {
  return new Set(
    String(Deno.env.get('BIZCONTROL_SYSTEM_ADMIN_EMAILS') || '')
      .split(',')
      .map(emailKey)
      .filter(Boolean),
  )
}

function resolveRedirect(input: unknown) {
  const allowed = String(Deno.env.get('BIZCONTROL_ALLOWED_REDIRECTS') || '')
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean)
  if (!allowed.length) throw new Error('BIZCONTROL_ALLOWED_REDIRECTS belum dikonfigurasi')

  const requested = String(input || allowed[0]).trim()
  let target: URL
  try { target = new URL(requested) } catch { throw new Error('Redirect URL tidak valid') }
  if (!['http:', 'https:'].includes(target.protocol)) throw new Error('Redirect URL tidak valid')

  const allowedOrigins = new Set(allowed.map((x) => new URL(x).origin))
  if (!allowedOrigins.has(target.origin)) throw new Error('Redirect origin tidak diizinkan')
  return target.toString()
}

async function findUserByEmail(admin: any, email: string) {
  const target = emailKey(email)
  const perPage = 200
  for (let page = 1; page <= 50; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage })
    if (error) throw error
    const users = data?.users || []
    const found = users.find((u: any) => emailKey(u.email) === target)
    if (found) return found
    if (users.length < perPage) break
  }
  return null
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: responseHeaders })
  if (req.method === 'GET') return json({ ok: true, service: 'account-admin', version: '1.8.7' })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
    if (!supabaseUrl || !serviceRoleKey) return json({ error: 'Server configuration missing' }, 500)

    const authHeader = req.headers.get('Authorization') || ''
    const token = authHeader.replace(/^Bearer\s+/i, '').trim()
    if (!token) return json({ error: 'Login diperlukan' }, 401)

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const { data: userData, error: userError } = await admin.auth.getUser(token)
    const actor = userData?.user
    if (userError || !actor) return json({ error: 'Sesi tidak valid atau sudah berakhir' }, 401)

    const payload = await req.json().catch(() => ({}))
    const action = String(payload.action || '').trim().toLowerCase()
    const actorEmail = emailKey(actor.email)
    const isSystemAdmin = configuredSystemAdmins().has(actorEmail)

    if (action === 'status') {
      return json({ ok: true, is_system_admin: isSystemAdmin })
    }

    if (action === 'list-owners') {
      if (!isSystemAdmin) return json({ error: 'Hanya Admin Sistem yang diizinkan' }, 403)
      const { data: owners, error: ownerError } = await admin
        .from('owner_accounts')
        .select('user_id,email,status,created_at,invited_at,activated_at')
        .order('created_at', { ascending: false })
      if (ownerError) throw ownerError
      const { data: businesses, error: businessError } = await admin.from('businesses').select('owner_id')
      if (businessError) throw businessError
      const counts = new Map<string, number>()
      for (const b of businesses || []) counts.set(b.owner_id, (counts.get(b.owner_id) || 0) + 1)
      return json({
        ok: true,
        owners: (owners || []).map((o: any) => ({ ...o, business_count: counts.get(o.user_id) || 0 })),
      })
    }

    if (action === 'invite-owner') {
      if (!isSystemAdmin) return json({ error: 'Hanya Admin Sistem yang dapat mendaftarkan Owner' }, 403)
      const email = emailKey(payload.email)
      if (!email || !email.includes('@') || email.length > 254) return json({ error: 'Email Owner tidak valid' }, 400)
      const redirectTo = resolveRedirect(payload.redirect_to)

      let targetUser = await findUserByEmail(admin, email)
      let status = 'active'
      let result = 'existing_user'

      if (!targetUser) {
        const { data: inviteData, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
          redirectTo,
          data: {
            bizcontrol_account_type: 'owner',
            bizcontrol_admin_invited: true,
          },
        })
        if (inviteError) throw inviteError
        targetUser = inviteData?.user
        if (!targetUser?.id) throw new Error('Supabase tidak mengembalikan user undangan')
        status = 'pending'
        result = 'invited'
      } else {
        const pendingInvite = Boolean(targetUser.invited_at && !targetUser.confirmed_at)
        status = pendingInvite ? 'pending' : 'active'
        result = pendingInvite ? 'pending_existing_invite' : 'existing_user'
      }

      const now = new Date().toISOString()
      const { error: upsertError } = await admin.from('owner_accounts').upsert({
        user_id: targetUser.id,
        email,
        status,
        invited_by: actor.id,
        invited_at: now,
        activated_at: status === 'active' ? now : null,
        updated_at: now,
      }, { onConflict: 'user_id' })
      if (upsertError) throw upsertError

      return json({
        ok: true,
        result,
        email,
        status,
        message: result === 'invited'
          ? 'Undangan Owner dikirim. Owner membuat password dari email lalu login ke BizControl.'
          : result === 'existing_user'
            ? 'Akun sudah ada. Hak Owner BizControl telah diaktifkan; user dapat login dengan password yang sudah dimiliki.'
            : 'Undangan Owner sebelumnya masih menunggu diterima.',
      })
    }

    if (action === 'reset-owner') {
      if (!isSystemAdmin) return json({ error: 'Hanya Admin Sistem yang dapat reset password Owner' }, 403)
      const email = emailKey(payload.email)
      if (!email || !email.includes('@')) return json({ error: 'Email Owner tidak valid' }, 400)
      const { data: ownerRow, error: ownerError } = await admin
        .from('owner_accounts')
        .select('user_id,email,status')
        .eq('email', email)
        .maybeSingle()
      if (ownerError) throw ownerError
      if (!ownerRow || ownerRow.status === 'disabled') return json({ error: 'Email tersebut bukan Owner aktif BizControl' }, 404)
      const redirectTo = resolveRedirect(payload.redirect_to)
      const { error: resetError } = await admin.auth.resetPasswordForEmail(email, { redirectTo })
      if (resetError) throw resetError
      return json({ ok: true, message: 'Link reset password Owner dikirim ke email yang terdaftar.' })
    }

    if (action === 'reset-member') {
      const businessId = String(payload.business_id || '').trim()
      const memberUserId = String(payload.user_id || '').trim()
      if (!/^[0-9a-f-]{36}$/i.test(businessId) || !/^[0-9a-f-]{36}$/i.test(memberUserId)) {
        return json({ error: 'Data anggota tidak valid' }, 400)
      }
      const { data: business, error: businessError } = await admin
        .from('businesses')
        .select('id,owner_id')
        .eq('id', businessId)
        .maybeSingle()
      if (businessError || !business) return json({ error: 'Bisnis tidak ditemukan' }, 404)
      if (business.owner_id !== actor.id) return json({ error: 'Hanya Owner bisnis yang dapat reset password karyawan' }, 403)

      const { data: member, error: memberError } = await admin
        .from('business_members')
        .select('user_id,status,role')
        .eq('business_id', businessId)
        .eq('user_id', memberUserId)
        .maybeSingle()
      if (memberError) throw memberError
      if (!member || member.status !== 'active') return json({ error: 'Anggota tidak aktif atau masih menunggu undangan' }, 404)

      const { data: targetData, error: targetError } = await admin.auth.admin.getUserById(memberUserId)
      if (targetError || !targetData?.user?.email) return json({ error: 'Email akun karyawan tidak ditemukan' }, 404)
      const targetEmail = emailKey(targetData.user.email)
      const redirectTo = resolveRedirect(payload.redirect_to)
      const { error: resetError } = await admin.auth.resetPasswordForEmail(targetEmail, { redirectTo })
      if (resetError) throw resetError

      await admin.from('audit_logs').insert({
        business_id: businessId,
        actor_user_id: actor.id,
        actor_email: actor.email || 'owner',
        action: 'SECURITY',
        module: 'team',
        record_id: memberUserId,
        record_label: targetEmail,
        before_data: null,
        after_data: { event: 'password_reset_requested', role: member.role },
        created_at: new Date().toISOString(),
      })

      return json({ ok: true, message: 'Link reset password karyawan dikirim ke email yang terdaftar.' })
    }

    return json({ error: 'Action tidak dikenal' }, 400)
  } catch (error) {
    console.error('account-admin error', error)
    return json({ error: (error as any)?.message || 'Gagal memproses administrasi akun' }, 400)
  }
})
