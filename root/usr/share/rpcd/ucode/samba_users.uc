#!/usr/bin/env ucode
'use strict';

/*
 * luci.samba_users - restricted RPC backend
 * - Edits /etc/passwd + /etc/group (no shadow-* tools)
 * - ksmbd (ksmbd.adduser) and/or Samba4 (smbpasswd/pdbedit)
 */

import { open, popen, readfile, writefile, unlink, stat } from 'fs';

const MIN_UID = 1000;
const MAX_UID = 60000;
const PASSWD_FILE = '/etc/passwd';
const GROUP_FILE  = '/etc/group';
const SHADOW_FILE = '/etc/shadow';
const KSMBD_PWDDB = '/etc/ksmbd/ksmbdpwd.db';

function trim(s) {
	return replace(replace(s || '', /^\s+/, ''), /\s+$/, '');
}

function is_valid_username(name) {
	return type(name) == 'string' &&
	       length(name) >= 1 && length(name) <= 32 &&
	       match(name, /^[a-z_][a-z0-9_-]*$/);
}

function shell_quote(s) {
	/* safe single-quoted shell string */
	return "'" + replace(s || '', /'/g, "'\\''") + "'";
}

function run(cmd) {
	let fp = popen(cmd + ' 2>&1', 'r');
	if (!fp)
		return { code: 255, out: 'popen failed' };
	let out = '';
	for (let line = fp.read('line'); line != null; line = fp.read('line'))
		out += line;
	let code = fp.close();
	return { code: code ?? 0, out: trim(out) };
}

function read_lines(path) {
	let data = readfile(path);
	if (data == null)
		return [];
	let lines = [];
	for (let line in split(data, '\n')) {
		line = trim(line);
		if (line != '')
			push(lines, line);
	}
	return lines;
}

function write_lines(path, lines) {
	let body = join('\n', lines) + '\n';
	let tmp = path + '.tmp.' + time();
	if (writefile(tmp, body) == null)
		return false;
	let rc = run(sprintf('mv -f %s %s', shell_quote(tmp), shell_quote(path))).code;
	if (rc != 0) {
		unlink(tmp);
		return false;
	}
	return true;
}

function get_used_uids() {
	let used = {};
	for (let line in read_lines(PASSWD_FILE)) {
		let parts = split(line, ':');
		if (length(parts) >= 3)
			used[int(parts[2])] = true;
	}
	return used;
}

function find_free_uid() {
	let used = get_used_uids();
	for (let uid = MIN_UID; uid <= MAX_UID; uid++)
		if (!used[uid])
			return uid;
	return null;
}

function user_exists(name) {
	for (let line in read_lines(PASSWD_FILE)) {
		let parts = split(line, ':');
		if (length(parts) >= 1 && parts[0] == name)
			return true;
	}
	return false;
}

function detect_backends() {
	let has_ksmbd     = run('command -v ksmbd.adduser').code == 0;
	let has_smbpasswd = run('command -v smbpasswd').code == 0;
	let has_pdbedit   = run('command -v pdbedit').code == 0;
	return {
		ksmbd: has_ksmbd,
		samba4: has_smbpasswd || has_pdbedit,
		smbpasswd: has_smbpasswd,
		pdbedit: has_pdbedit
	};
}

function list_samba4_users() {
	let users = [];
	let res = run('pdbedit -L');
	if (res.code == 0 && length(res.out) > 0) {
		for (let line in split(res.out, '\n')) {
			line = trim(line);
			if (line == '') continue;
			let parts = split(line, ':');
			if (length(parts) >= 1 && parts[0] != '')
				push(users, parts[0]);
		}
		return users;
	}
	res = run('cat /etc/samba/smbpasswd');
	for (let line in split(res.out, '\n')) {
		line = trim(line);
		if (line == '' || match(line, /^#/)) continue;
		let parts = split(line, ':');
		if (length(parts) >= 1 && parts[0] != '')
			push(users, parts[0]);
	}
	return users;
}

/* Best-effort: usernames often appear as plain strings in ksmbdpwd.db */
function list_ksmbd_users_guess() {
	let users = [];
	let st = stat(KSMBD_PWDDB);
	if (!st) return users;
	let res = run(sprintf('strings %s', shell_quote(KSMBD_PWDDB)));
	if (res.code != 0 || length(res.out) == 0) return users;
	let seen = {};
	for (let tok in split(res.out, '\n')) {
		tok = trim(tok);
		if (!match(tok, /^[a-z_][a-z0-9_-]*$/)) continue;
		if (length(tok) < 1 || length(tok) > 32) continue;
		if (tok == 'root' || tok == 'nobody' || tok == 'daemon') continue;
		if (seen[tok]) continue;
		seen[tok] = true;
		push(users, tok);
	}
	return users;
}

function list_system_candidates() {
	let result = [];
	for (let line in read_lines(PASSWD_FILE)) {
		let parts = split(line, ':');
		if (length(parts) < 7) continue;
		let name  = parts[0];
		let uid   = int(parts[2]);
		let gid   = int(parts[3]);
		let shell = parts[6];
		if (name == 'nobody' || name == 'nfsnobody') continue;
		/* Include all normal accounts UID>=1000 (not only nologin shells).
		   Manually created users via useradd may use various shells. */
		if (uid >= MIN_UID && uid <= MAX_UID) {
			push(result, {
				username: name,
				uid: uid,
				gid: gid,
				shell: shell
			});
		}
	}
	return result;
}

function create_system_user(username, uid) {
	let passwd_lines = read_lines(PASSWD_FILE);
	let group_lines  = read_lines(GROUP_FILE);

	for (let line in passwd_lines) {
		let p = split(line, ':');
		if (p[0] == username)
			return { ok: false, error: 'User already in passwd' };
	}

	push(passwd_lines, sprintf('%s:x:%d:%d:smb user:/dev/null:/bin/false', username, uid, uid));
	push(group_lines,  sprintf('%s:x:%d:', username, uid));

	if (!write_lines(PASSWD_FILE, passwd_lines))
		return { ok: false, error: 'Failed to write /etc/passwd' };
	if (!write_lines(GROUP_FILE, group_lines)) {
		passwd_lines = filter(passwd_lines, l => split(l, ':')[0] != username);
		write_lines(PASSWD_FILE, passwd_lines);
		return { ok: false, error: 'Failed to write /etc/group' };
	}

	let shadow_lines = read_lines(SHADOW_FILE);
	let has_shadow = false;
	for (let line in shadow_lines)
		if (split(line, ':')[0] == username) { has_shadow = true; break; }
	if (!has_shadow) {
		push(shadow_lines, sprintf('%s:!:0:0:99999:7:::', username));
		write_lines(SHADOW_FILE, shadow_lines);
	}

	return { ok: true };
}

function remove_system_user(username) {
	let passwd_lines = filter(read_lines(PASSWD_FILE), l => split(l, ':')[0] != username);
	let group_lines  = filter(read_lines(GROUP_FILE),  l => split(l, ':')[0] != username);
	let shadow_lines = filter(read_lines(SHADOW_FILE), l => split(l, ':')[0] != username);
	write_lines(PASSWD_FILE, passwd_lines);
	write_lines(GROUP_FILE,  group_lines);
	write_lines(SHADOW_FILE, shadow_lines);
	return true;
}

function add_smb_password(username, password, backends) {
	let errors = [];

	if (backends.ksmbd) {
		/* ksmbd.adduser -a -p PWD USER  (PWD must not be empty for -a in practice) */
		let cmd = sprintf('ksmbd.adduser -a -p %s %s', shell_quote(password), shell_quote(username));
		let res = run(cmd);
		if (res.code == 0)
			return { ok: true, backend: 'ksmbd' };
		push(errors, 'ksmbd.adduser: ' + (res.out || ('exit ' + res.code)));
	}

	if (backends.smbpasswd) {
		let tmp = sprintf('/tmp/.smbpass.%d', time());
		if (writefile(tmp, password + '\n' + password + '\n') == null) {
			push(errors, 'temp password file failed');
		} else {
			run(sprintf('chmod 600 %s', shell_quote(tmp)));
			let res = run(sprintf('smbpasswd -a -s %s < %s', shell_quote(username), shell_quote(tmp)));
			unlink(tmp);
			if (res.code == 0)
				return { ok: true, backend: 'samba4' };
			push(errors, 'smbpasswd: ' + (res.out || ('exit ' + res.code)));
		}
	}

	if (length(errors) == 0)
		return { ok: false, error: 'No SMB backend available (install ksmbd-utils or samba4-utils)' };
	return { ok: false, error: join('; ', errors) };
}

function remove_smb_password(username, backends) {
	if (backends.ksmbd)
		run(sprintf('ksmbd.adduser -d %s', shell_quote(username)));
	if (backends.smbpasswd)
		run(sprintf('smbpasswd -x %s', shell_quote(username)));
	if (backends.pdbedit)
		run(sprintf('pdbedit -x -u %s', shell_quote(username)));
	return true;
}

function change_smb_password(username, password, backends) {
	let errors = [];

	if (backends.ksmbd) {
		let cmd = sprintf('ksmbd.adduser -u -p %s %s', shell_quote(password), shell_quote(username));
		let res = run(cmd);
		if (res.code == 0)
			return { ok: true, backend: 'ksmbd' };
		push(errors, 'ksmbd.adduser -u: ' + (res.out || ('exit ' + res.code)));
	}

	if (backends.smbpasswd) {
		let tmp = sprintf('/tmp/.smbpass.%d', time());
		if (writefile(tmp, password + '\n' + password + '\n') == null) {
			push(errors, 'temp password file failed');
		} else {
			run(sprintf('chmod 600 %s', shell_quote(tmp)));
			let res = run(sprintf('smbpasswd -s %s < %s', shell_quote(username), shell_quote(tmp)));
			unlink(tmp);
			if (res.code == 0)
				return { ok: true, backend: 'samba4' };
			push(errors, 'smbpasswd: ' + (res.out || ('exit ' + res.code)));
		}
	}

	if (length(errors) == 0)
		return { ok: false, error: 'No SMB backend available' };
	return { ok: false, error: join('; ', errors) };
}

const methods = {
	list_users: {
		call: function() {
			let backends = detect_backends();
			let system   = list_system_candidates();
			let samba4   = backends.samba4 ? list_samba4_users() : [];
			let ksmbd_u  = backends.ksmbd ? list_ksmbd_users_guess() : [];
			let out = [];
			let seen = {};

			for (let u in system) {
				seen[u.username] = true;
				let in_samba4 = false;
				for (let s in samba4)
					if (s == u.username) { in_samba4 = true; break; }
				let in_ksmbd = false;
				for (let k in ksmbd_u)
					if (k == u.username) { in_ksmbd = true; break; }
				/* If ksmbd backend exists and user is a normal account, treat as possible ksmbd user
				   even if strings() did not find the name (db format varies). */
				if (backends.ksmbd && !in_ksmbd)
					in_ksmbd = true;
				push(out, {
					username: u.username,
					uid: u.uid,
					gid: u.gid,
					in_samba: in_samba4 || in_ksmbd,
					in_samba4: in_samba4,
					in_ksmbd: in_ksmbd
				});
			}

			for (let s in samba4) {
				if (!seen[s]) {
					seen[s] = true;
					push(out, {
						username: s,
						uid: null,
						gid: null,
						in_samba: true,
						in_samba4: true,
						in_ksmbd: false
					});
				}
			}

			for (let k in ksmbd_u) {
				if (!seen[k]) {
					seen[k] = true;
					push(out, {
						username: k,
						uid: null,
						gid: null,
						in_samba: true,
						in_samba4: false,
						in_ksmbd: true
					});
				}
			}

			return { users: out, backends: backends };
		}
	},

	get_status: {
		call: function() {
			let b = detect_backends();
			return {
				ksmbd: b.ksmbd,
				samba4: b.samba4,
				smbpasswd: b.smbpasswd,
				pdbedit: b.pdbedit,
				min_uid: MIN_UID,
				method: 'passwd-file'
			};
		}
	},

	add_user: {
		args: {
			username: '',
			password: ''
		},
		call: function(req) {
			let username = trim((req.args && req.args.username) || '');
			let password = (req.args && req.args.password) || '';

			if (!is_valid_username(username))
				return { success: false, error: 'Invalid username. Use 1-32 chars matching [a-z_][a-z0-9_-]*' };

			if (length(password) < 1)
				return { success: false, error: 'Password must not be empty' };

			if (user_exists(username))
				return { success: false, error: 'System user already exists' };

			let backends = detect_backends();
			if (!backends.ksmbd && !backends.samba4)
				return { success: false, error: 'No SMB backend found. Install ksmbd-utils and/or samba4-utils.' };

			let uid = find_free_uid();
			if (uid == null)
				return { success: false, error: 'No free UID available' };

			let sys = create_system_user(username, uid);
			if (!sys.ok)
				return { success: false, error: sys.error };

			let smb = add_smb_password(username, password, backends);
			if (!smb.ok) {
				remove_system_user(username);
				return { success: false, error: smb.error };
			}

			return {
				success: true,
				username: username,
				uid: uid,
				gid: uid,
				backend: smb.backend,
				message: 'User created successfully'
			};
		}
	},

	remove_user: {
		args: {
			username: ''
		},
		call: function(req) {
			let username = trim((req.args && req.args.username) || '');

			if (!is_valid_username(username))
				return { success: false, error: 'Invalid username' };

			if (username == 'root' || username == 'nobody' || username == 'daemon')
				return { success: false, error: 'Refusing to remove protected account' };

			let backends = detect_backends();
			remove_smb_password(username, backends);
			remove_system_user(username);

			return {
				success: true,
				username: username,
				message: 'User removed'
			};
		}
	},

	change_password: {
		args: {
			username: '',
			password: ''
		},
		call: function(req) {
			let username = trim((req.args && req.args.username) || '');
			let password = (req.args && req.args.password) || '';

			if (!is_valid_username(username))
				return { success: false, error: 'Invalid username' };

			if (length(password) < 1)
				return { success: false, error: 'Password must not be empty' };

			if (!user_exists(username))
				return { success: false, error: 'System user does not exist' };

			let backends = detect_backends();
			let res = change_smb_password(username, password, backends);
			if (!res.ok)
				return { success: false, error: res.error };

			return {
				success: true,
				username: username,
				backend: res.backend,
				message: 'Password updated'
			};
		}
	}
};

return { 'luci.samba_users': methods };
