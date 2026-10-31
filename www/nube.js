/* Gasoleros Metropol · conexión a la base compartida (Supabase)
   Requiere supabase.js cargado antes. La URL y la clave "anon" son públicas por diseño:
   la seguridad la dan las reglas de la base (ver supabase/01_base_compartida.sql). */
(function () {
  var URL = 'https://borabvkfnehswdxkxrfj.supabase.co';
  var KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJvcmFidmtmbmVoc3dkeGt4cmZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyNDYzMDEsImV4cCI6MjEwODgyMjMwMX0.Xf0SKS9icN1ZXV9Tpd0kP_27GgtLy2yaunMqyW4iPnI';
  var CACHE = 'nube_estado_v1';
  var enabled = !!(window.supabase && window.supabase.createClient);
  var sb = null;
  if (enabled) {
    try {
      sb = window.supabase.createClient(URL, KEY, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false, storageKey: 'gasoleros-auth' },
        realtime: { params: { eventsPerSecond: 5 } }
      });
    } catch (e) { enabled = false; }
  }

  var N = { enabled: enabled, sb: sb, session: null, perfil: null, turno: null, online: true };
  var subs = [];
  N.on = function (fn) { subs.push(fn); };
  function emit() { subs.forEach(function (f) { try { f(N); } catch (e) {} }); }

  function email(l) { return String(l).trim() + '@gasoleros.app'; }
  function msgErr(e) {
    var m = (e && (e.message || e.error_description || e.msg)) || String(e || 'Error');
    if (/Invalid login credentials/i.test(m)) return 'Legajo o contraseña incorrectos.';
    if (/already registered|already been registered/i.test(m)) return 'Ese legajo ya tiene una cuenta.';
    if (/Password should be at least/i.test(m)) return 'La contraseña tiene que tener al menos 6 caracteres.';
    if (/Database error saving new user/i.test(m)) return 'No se pudo crear la cuenta. Revisá que el legajo sea solo números (3 a 8 cifras).';
    if (/Failed to fetch|NetworkError|Load failed/i.test(m)) return 'Sin conexión. Probá de nuevo cuando tengas señal.';
    if (/Email not confirmed/i.test(m)) return 'La cuenta todavía no está confirmada. Avisale al administrador.';
    return m;
  }
  N.msgErr = msgErr;

  function save() {
    try { localStorage.setItem(CACHE, JSON.stringify({ perfil: N.perfil, turno: N.turno, logged: !!N.session })); } catch (e) {}
  }
  function loadCache() {
    try { var c = JSON.parse(localStorage.getItem(CACHE) || 'null'); if (c) { N.perfil = c.perfil; N.turno = c.turno; N._cachedLogged = !!c.logged; } } catch (e) {}
  }
  loadCache();

  /* ¿hay sesión? ¿está habilitado? ¿está en turno? */
  N.logged = function () { return !!(N.session || (N._cachedLogged && N.perfil)); };
  N.activo = function () { return !!(N.perfil && N.perfil.activo); };
  N.admin = function () { return !!(N.perfil && N.perfil.activo && N.perfil.rol === 'admin'); };
  N.enTurno = function () { return N.activo() && !!N.turno && !N.turno.fin && new Date(N.turno.fin_prog).getTime() > Date.now(); };

  N.refresh = async function () {
    if (!enabled) return N;
    try {
      var s = await sb.auth.getSession();
      N.session = (s && s.data && s.data.session) || null;
      if (!N.session) { N.perfil = null; N.turno = null; N._cachedLogged = false; save(); emit(); return N; }
      var uid = N.session.user.id;
      var p = await sb.from('perfiles').select('*').eq('id', uid).maybeSingle();
      if (p.error) throw p.error;
      N.perfil = p.data;
      N.turno = null;
      if (N.perfil && N.perfil.activo) {
        var t = await sb.from('turnos').select('*').eq('user_id', uid).is('fin', null)
          .gt('fin_prog', new Date().toISOString()).order('inicio', { ascending: false }).limit(1);
        if (t.error) throw t.error;
        N.turno = (t.data && t.data[0]) || null;
      }
      N.online = true; N._cachedLogged = true; save();
    } catch (e) {
      N.online = false;   /* sin señal: se sigue con lo último que se sabía */
    }
    emit();
    return N;
  };

  N.login = async function (legajo, clave) {
    var r = await sb.auth.signInWithPassword({ email: email(legajo), password: clave });
    if (r.error) throw new Error(msgErr(r.error));
    await N.refresh();
    return N;
  };
  N.registrar = async function (legajo, nombre, clave) {
    var r = await sb.auth.signUp({ email: email(legajo), password: clave, options: { data: { legajo: String(legajo).trim(), nombre: String(nombre || '').trim() } } });
    if (r.error) throw new Error(msgErr(r.error));
    if (!r.data.session) throw new Error('La cuenta se creó pero el servidor pide confirmar el mail. Avisale al administrador (hay que desactivar "Confirm email").');
    await N.refresh();
    return N;
  };
  N.salir = async function () {
    try { await sb.auth.signOut(); } catch (e) {}
    N.session = null; N.perfil = null; N.turno = null; N._cachedLogged = false; save(); emit();
  };
  N.cambiarClave = async function (clave) {
    var r = await sb.auth.updateUser({ password: clave });
    if (r.error) throw new Error(msgErr(r.error));
  };

  N.iniciarTurno = async function (t) {
    var r = await sb.rpc('iniciar_turno', { p_turno: t });
    if (r.error) throw new Error(msgErr(r.error));
    await N.refresh();
  };
  N.terminarTurno = async function () {
    var r = await sb.rpc('terminar_turno');
    if (r.error) throw new Error(msgErr(r.error));
    await N.refresh();
  };
  N.quienEnTurno = async function () {
    var r = await sb.rpc('quien_en_turno');
    if (r.error) throw new Error(msgErr(r.error));
    return r.data || [];
  };
  N.auditoria = async function (n) {
    var r = await sb.from('auditoria').select('*').order('id', { ascending: false }).limit(n || 150);
    if (r.error) throw new Error(msgErr(r.error));
    return r.data || [];
  };
  N.usuarios = async function () {
    var r = await sb.from('perfiles').select('*').order('creado', { ascending: true });
    if (r.error) throw new Error(msgErr(r.error));
    return r.data || [];
  };
  N.setUsuario = async function (id, activo, rol) {
    var r = await sb.rpc('admin_set_usuario', { p_id: id, p_activo: activo, p_rol: rol });
    if (r.error) throw new Error(msgErr(r.error));
  };

  window.Nube = N;
  if (enabled) {
    sb.auth.onAuthStateChange(function () { setTimeout(function () { N.refresh(); }, 0); });
    window.addEventListener('online', function () { N.refresh(); });
  }
})();
