'use strict';
'require view';
'require rpc';
'require ui';

var callListUsers = rpc.declare({
	object: 'luci.samba_users',
	method: 'list_users'
});

var callGetStatus = rpc.declare({
	object: 'luci.samba_users',
	method: 'get_status'
});

var callAddUser = rpc.declare({
	object: 'luci.samba_users',
	method: 'add_user',
	params: [ 'username', 'password' ]
});

var callRemoveUser = rpc.declare({
	object: 'luci.samba_users',
	method: 'remove_user',
	params: [ 'username' ]
});

var callChangePassword = rpc.declare({
	object: 'luci.samba_users',
	method: 'change_password',
	params: [ 'username', 'password' ]
});

return view.extend({
	load: function() {
		return Promise.all([
			callListUsers().catch(function(e) {
				return { __rpc_error: String(e && e.message ? e.message : e) };
			}),
			callGetStatus().catch(function(e) {
				return { __rpc_error: String(e && e.message ? e.message : e) };
			})
		]);
	},

	render: function(data) {
		var listRes = data[0];
		var status  = data[1] || {};
		var users = [];
		var debug = '';

		try {
			debug = JSON.stringify(listRes);
		} catch (e) {
			debug = String(listRes);
		}

		if (listRes && listRes.users && listRes.users.length !== undefined) {
			users = listRes.users;
		}

		var body = E('div', { 'class': 'cbi-map' });

		body.appendChild(E('h2', {}, [ 'Samba / ksmbd User Manager' ]));

		/* Debug line - remove later once list works */
		body.appendChild(E('div', {
			'class': 'alert-message warning',
			'style': 'font-family:monospace;font-size:11px;word-break:break-all'
		}, [ 'RPC list_users raw: ', debug || '(empty)' ]));

		if (listRes && listRes.__rpc_error) {
			body.appendChild(E('div', { 'class': 'alert-message error' }, [
				'List RPC error: ' + listRes.__rpc_error
			]));
		}

		var bits = [];
		if (status.ksmbd) bits.push('ksmbd');
		if (status.samba4) bits.push('Samba4');
		if (bits.length)
			body.appendChild(E('div', { 'class': 'alert-message notice' }, [
				'Active backends: ' + bits.join(', ')
			]));

		/* ---- Add form ---- */
		var form = E('div', { 'class': 'cbi-section' });
		form.appendChild(E('h3', {}, [ 'Add user' ]));

		function field(label, input) {
			var row = E('div', { 'class': 'cbi-value' });
			row.appendChild(E('label', { 'class': 'cbi-value-title' }, [ label ]));
			row.appendChild(E('div', { 'class': 'cbi-value-field' }, [ input ]));
			return row;
		}

		form.appendChild(field('Username', E('input', {
			'type': 'text', 'id': 'su-username', 'class': 'cbi-input-text',
			'autocomplete': 'off', 'spellcheck': 'false'
		})));
		form.appendChild(field('Password', E('input', {
			'type': 'password', 'id': 'su-password',
			'class': 'cbi-input-password', 'autocomplete': 'new-password'
		})));
		form.appendChild(field('Confirm password', E('input', {
			'type': 'password', 'id': 'su-password2',
			'class': 'cbi-input-password', 'autocomplete': 'new-password'
		})));

		var btnRow = E('div', { 'class': 'cbi-value' });
		btnRow.appendChild(E('label', { 'class': 'cbi-value-title' }, [ '' ]));
		btnRow.appendChild(E('div', { 'class': 'cbi-value-field' }, [
			E('button', {
				'class': 'cbi-button cbi-button-apply',
				'click': ui.createHandlerFn(this, 'handleAddUser')
			}, [ 'Add user' ])
		]));
		form.appendChild(btnRow);
		body.appendChild(form);

		/* ---- User list (built fully here) ---- */
		var section = E('div', { 'class': 'cbi-section' });
		section.appendChild(E('h3', {}, [ 'Existing users (' + users.length + ')' ]));

		if (!users.length) {
			section.appendChild(E('p', {}, [ 'No managed users found.' ]));
		} else {
			var table = E('table', { 'class': 'table' });
			table.appendChild(E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, [ 'Username' ]),
				E('th', { 'class': 'th' }, [ 'UID' ]),
				E('th', { 'class': 'th' }, [ 'GID' ]),
				E('th', { 'class': 'th' }, [ 'Backend' ]),
				E('th', { 'class': 'th' }, [ 'Actions' ])
			]));

			for (var i = 0; i < users.length; i++) {
				var u = users[i];
				var be = [];
				if (u.in_samba4) be.push('Samba4');
				if (u.in_ksmbd) be.push('ksmbd');
				table.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, [ String(u.username || '') ]),
					E('td', { 'class': 'td' }, [ u.uid != null ? String(u.uid) : '-' ]),
					E('td', { 'class': 'td' }, [ u.gid != null ? String(u.gid) : '-' ]),
					E('td', { 'class': 'td' }, [ be.join(', ') || '-' ]),
					E('td', { 'class': 'td' }, [
						E('button', {
							'class': 'cbi-button cbi-button-action',
							'click': ui.createHandlerFn(this, 'handleChangePassword', u.username)
						}, [ 'Password' ]),
						' ',
						E('button', {
							'class': 'cbi-button cbi-button-negative',
							'click': ui.createHandlerFn(this, 'handleRemoveUser', u.username)
						}, [ 'Remove' ])
					])
				]));
			}
			section.appendChild(table);
		}
		body.appendChild(section);

		return body;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	handleAddUser: function() {
		var username  = (document.getElementById('su-username').value || '').trim();
		var password  = document.getElementById('su-password').value || '';
		var password2 = document.getElementById('su-password2').value || '';

		if (!username) {
			ui.addNotification(null, E('p', {}, [ 'Username is required' ]), 'error');
			return;
		}
		if (!password) {
			ui.addNotification(null, E('p', {}, [ 'Password is required' ]), 'error');
			return;
		}
		if (password !== password2) {
			ui.addNotification(null, E('p', {}, [ 'Passwords do not match' ]), 'error');
			return;
		}

		return callAddUser(username, password).then(function(res) {
			if (res && res.success) {
				ui.addNotification(null, E('p', {}, [
					'User "' + res.username + '" created (UID ' + res.uid + ', backend ' + (res.backend || '') + ')'
				]), 'info');
				location.reload();
			} else {
				ui.addNotification(null, E('p', {}, [
					(res && res.error) ? res.error : 'Failed to create user'
				]), 'error');
			}
		}).catch(function(err) {
			ui.addNotification(null, E('p', {}, [
				'RPC error: ' + (err.message || err)
			]), 'error');
		});
	},

	handleRemoveUser: function(username) {
		return ui.showModal('Confirm removal', [
			E('p', {}, [ 'Really remove user "' + username + '"?' ]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ 'Cancel' ]),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-negative',
					'click': ui.createHandlerFn(this, function() {
						ui.hideModal();
						return callRemoveUser(username).then(function(res) {
							if (res && res.success) {
								ui.addNotification(null, E('p', {}, [ 'User removed' ]), 'info');
								location.reload();
							} else {
								ui.addNotification(null, E('p', {}, [
									(res && res.error) ? res.error : 'Failed to remove'
								]), 'error');
							}
						});
					})
				}, [ 'Remove' ])
			])
		]);
	},

	handleChangePassword: function(username) {
		var pwd1 = E('input', { 'type': 'password', 'class': 'cbi-input-password', 'style': 'width:100%' });
		var pwd2 = E('input', { 'type': 'password', 'class': 'cbi-input-password', 'style': 'width:100%' });
		return ui.showModal('Change password for "' + username + '"', [
			E('div', {}, [ E('label', {}, [ 'New password' ]), pwd1 ]),
			E('div', {}, [ E('label', {}, [ 'Confirm' ]), pwd2 ]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ 'Cancel' ]),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-positive',
					'click': ui.createHandlerFn(this, function() {
						if (!pwd1.value) {
							ui.addNotification(null, E('p', {}, [ 'Password required' ]), 'error');
							return;
						}
						if (pwd1.value !== pwd2.value) {
							ui.addNotification(null, E('p', {}, [ 'Passwords do not match' ]), 'error');
							return;
						}
						ui.hideModal();
						return callChangePassword(username, pwd1.value).then(function(res) {
							if (res && res.success)
								ui.addNotification(null, E('p', {}, [ 'Password updated' ]), 'info');
							else
								ui.addNotification(null, E('p', {}, [
									(res && res.error) ? res.error : 'Failed'
								]), 'error');
						});
					})
				}, [ 'Change' ])
			])
		]);
	}
});
