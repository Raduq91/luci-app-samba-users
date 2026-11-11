#!/usr/bin/env ucode
'use strict';

/*
 * luci.samba_users – restricted RPC backend
 *
 * - Creates / removes system accounts by editing /etc/passwd and /etc/group
 *   (no shadow-useradd / userdel / groupadd required)
 * - Supports both Samba4 (smbpasswd / pdbedit) and ksmbd (ksmbd.adduser)
 * - Passwords never appear on a process command line where avoidable
 */

import { popen } from 'fs';

const MIN_UID = 1000;
const MAX_UID = 60000;
const PASSWD_FILE = '/etc/passwd';
const GROUP_FILE  = '/etc/group';
const SHADOW_FILE = '/etc/shadow';

function trim(s) {
	return replace(replace(s || '', /^\s+/, ''), /\s+$/, '');
}

function is_valid_username(name) {
	return type(name) == 'string' &&
	       length(name) >= 1 && length(name) <= 32 &&
	       match(name, /^[a-z_][a-z0-9_-]*$/);
}

function run(cmd) {
	let fp = popen(cmd, 'r');
	if (!fp)
		return { code: 255, out: '' };
	let out = '';
	for (let line = fp.read('line'); line != null; line = fp.read('line'))
		out += line;
	let code = fp.close();
	return { code: code ?? 0, out: out };
}

function read_lines(path) {
	let res = run(sprintf('cat %s 2>/dev/null', path));
	let lines = [];
	for (let line in split(res.out, '\n')) {
		line = trim(line);
		if (line != '')
			push(lines, line);
	}
	return lines;
}

function write_lines(path, lines) {
	let tmp = path + '.tmp.' + time();
	let fp = open(tmp, 'w');
	if (!fp)
		return false;
	for (let line in lines)
		fp.write(line + '\n');
	fp.close();
	let rc = run(sprintf('mv -f %s %s', tmp, path)).code;
	return rc == 0;
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
	let has_ksmbd     = run('command -v ksmbd.adduser >/dev/null 2>&1').code == 0;
	let has_smbpasswd = run('command -v smbpasswd >/dev/null 2>&1').code == 0;
	let has_pdbedit   = run('command -v pdbedit >/dev/null 2>&1').code == 0;
	return {
		ksmbd: has_ksmbd,
		samba4: has_smbpasswd || has_pdbedit,
		smbpasswd: has_smbpasswd,
		pdbedit: has_pdbedit
	};
}

function list_samba4_users() {
	let users = [];
	let res = run('pdbedit -L 2>/dev/null');
	if (res.code == 0 && length(trim(res.out)) > 0) {
		for (let line in split(res.out, '\n')) {
			line = trim(line);
			if (line == '') continue;
			let parts = split(line, ':');
			if (length(parts) >= 1 && parts[0] != '')
				push(users, parts[0]);
		}
		return users;
	}
	res = run('cat /etc/samba/smbpasswd 2>/dev/null');
	for (let line in split(res.out, '\n')) {
		line = trim(line);
		if (line == '' || match(line, /^#/)) continue;
		let parts = split(line, ':');
		if (length(parts) >= 1 && parts[0] != '')
			push(users, parts[0]);
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
		if (uid >= MIN_UID && uid <= MAX_UID &&
		    (shell == '/bin/false' || shell == '/usr/sbin/nologin' ||
		     shell == '/sbin/nologin' || shell == '/dev/null')) {
			push(result, { username: name, uid: uid, gid: gid, shell: shell });
		}
	}
	return result;
}

function write_temp_password(password) {
	let tmp = sprintf('/tmp/.smbpass.%d', time());
	let fp = open(tmp, 'w');
	if (!fp) return null;
	fp.write(password + '\n' + password + '\n');
	fp.close();
	run(sprintf('chmod 600 %s', tmp));
	return tmp;
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
		let tmp = write_temp_password(password);
		if (tmp) {
			let rc = run(sprintf(
				'sh -c \'PASS=$(head -n1 %s); ksmbd.adduser -a -p "$PASS" %s\' 2>/dev/null',
				tmp, username
			)).code;
			run(sprintf('rm -f %s', tmp));
			if (rc == 0)
				return { ok: true, backend: 'ksmbd' };
			push(errors, 'ksmbd.adduser failed');
		} else {
			push(errors, 'temp file failed');
		}
	}

	if (backends.smbpasswd) {
		let tmp = write_temp_password(password);
		if (!tmp)
			return { ok: false, error: 'Cannot create temporary password file' };
		let rc = run(sprintf('smbpasswd -a -s %s < %s 2>/dev/null', username, tmp)).code;
		run(sprintf('rm -f %s', tmp));
		if (rc == 0)
			return { ok: true, backend: 'samba4' };
		push(errors, 'smbpasswd failed');
	}

	if (length(errors) == 0)
		return { ok: false, error: 'No SMB backend available (install ksmbd-utils or samba4-utils)' };
	return { ok: false, error: join('; ', errors) };
}

function remove_smb_password(username, backends) {
	if (backends.ksmbd)
		run(sprintf('ksmbd.adduser -d %s 2>/dev/null', username));
	if (backends.smbpasswd)
		run(sprintf('smbpasswd -x %s 2>/dev/null', username));
	if (backends.pdbedit)
		run(sprintf('pdbedit -x -u %s 2>/dev/null', username));
	return true;
}

function change_smb_password(username, password, backends) {
	let errors = [];

	if (backends.ksmbd) {
		let tmp = write_temp_password(password);
		if (tmp) {
			let rc = run(sprintf(
				'sh -c \'PASS=$(head -n1 %s); ksmbd.adduser -u -p "$PASS" %s\' 2>/dev/null',
				tmp, username
			)).code;
			run(sprintf('rm -f %s', tmp));
			if (rc == 0)
				return { ok: true, backend: 'ksmbd' };
			push(errors, 'ksmbd.adduser -u failed');
		}
	}

	if (backends.smbpasswd) {
		let tmp = write_temp_password(password);
		if (!tmp)
			return { ok: false, error: 'Cannot create temporary password file' };
		let rc = run(sprintf('smbpasswd -s %s < %s 2>/dev/null', username, tmp)).code;
		run(sprintf('rm -f %s', tmp));
		if (rc == 0)
			return { ok: true, backend: 'samba4' };
		push(errors, 'smbpasswd failed');
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
			let out = [];
			let seen = {};

			for (let u in system) {
				seen[u.username] = true;
				let in_samba4 = false;
				for (let s in samba4)
					if (s == u.username) { in_samba4 = true; break; }
				push(out, {
					username: u.username,
					uid: u.uid,
					gid: u.gid,
					in_samba: in_samba4 || backends.ksmbd,
					in_samba4: in_samba4,
					in_ksmbd: backends.ksmbd
				});
			}

			for (let s in samba4) {
				if (!seen[s])
					push(out, {
						username: s,
						uid: null,
						gid: null,
						in_samba: true,
						in_samba4: true,
						in_ksmbd: false
					});
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
