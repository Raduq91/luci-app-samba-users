'use strict';
'require view';
'require rpc';
'require ui';

const callListUsers = rpc.declare({
	object: 'luci.samba_users',
	method: 'list_users'
});

const callGetStatus = rpc.declare({
	object: 'luci.samba_users',
	method: 'get_status'
});

const callAddUser = rpc.declare({
	object: 'luci.samba_users',
	method: 'add_user',
	params: [ 'username', 'password' ]
});

const callRemoveUser = rpc.declare({
	object: 'luci.samba_users',
	method: 'remove_user',
	params: [ 'username' ]
});

const callChangePassword = rpc.declare({
	object: 'luci.samba_users',
	method: 'change_password',
	params: [ 'username', 'password' ]
});

return view.extend({
	load: function() {
		return Promise.all([
			callListUsers().catch(function(e) { return { _error: String(e.message || e), users: [] }; }),
			callGetStatus().catch(function(e) { return { _error: String(e.message || e) }; })
		]);
	},

	render: function(data) {
		const listRes = data[0] || {};
		const status  = data[1] || {};
		const users   = Array.isArray(listRes.users) ? listRes.users : [];

		let body = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ _('Samba / ksmbd User Manager') ]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Create and manage share users. System accounts are created by editing /etc/passwd and /etc/group.')
			])
		]);

		if (listRes._error) {
			body.appendChild(E('div', { 'class': 'alert-message error' }, [
				_('Failed to list users (RPC): %s').format(listRes._error),
				E('br'),
				_('Log out of LuCI completely, log back in, then refresh. ACL may not be applied yet.')
			]));
		}

		const backendBits = [];
		if (status.ksmbd)  backendBits.push('ksmbd');
		if (status.samba4) backendBits.push('Samba4');
		if (status._error) {
			body.appendChild(E('div', { 'class': 'alert-message warning' }, [
				_('Status RPC error: %s').format(status._error)
			]));
		} else if (backendBits.length === 0) {
			body.appendChild(E('div', { 'class': 'alert-message warning' }, [
				_('No SMB backend detected (ksmbd.adduser / smbpasswd not found in PATH for rpcd).')
			]));
		} else {
			body.appendChild(E('div', { 'class': 'alert-message notice' }, [
				_('Active backends: %s').format(backendBits.join(', '))
			]));
		}

		/* Add-user form */
		body.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Add user') ]),
			E('div', { 'class': 'cbi-section-node' }, [
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, [ _('Username') ]),
					E('div', { 'class': 'cbi-value-field' }, [
						E('input', {
							'type': 'text',
							'id': 'su-username',
							'class': 'cbi-input-text',
							'placeholder': 'myuser',
							'autocomplete': 'off',
							'spellcheck': 'false'
						}),
						E('div', { 'class': 'cbi-value-description' }, [
							_('Lowercase letters, digits, underscore and hyphen. Must start with a letter or underscore.')
						])
					])
				]),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, [ _('Password') ]),
					E('div', { 'class': 'cbi-value-field' }, [
						E('input', {
							'type': 'password',
							'id': 'su-password',
							'class': 'cbi-input-password',
							'autocomplete': 'new-password'
						})
					])
				]),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, [ _('Confirm password') ]),
					E('div', { 'class': 'cbi-value-field' }, [
						E('input', {
							'type': 'password',
							'id': 'su-password2',
							'class': 'cbi-input-password',
							'autocomplete': 'new-password'
						})
					])
				]),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }),
					E('div', { 'class': 'cbi-value-field' }, [
						E('button', {
							'class': 'cbi-button cbi-button-apply',
							'click': ui.createHandlerFn(this, 'handleAddUser')
						}, [ _('Add user') ])
					])
				])
			])
		]));

		body.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Existing users') ]),
			E('div', { 'class': 'cbi-section-node', 'id': 'su-user-list' })
		]));

		this._initialUsers = users;
		/* Fill table after node is in the document */
		const self = this;
		setTimeout(function() { self.renderUserTable(users); }, 0);
		return body;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	renderUserTable: function(users) {
		const container = document.getElementById('su-user-list');
		if (!container) return;
		container.innerHTML = '';

		if (!users || users.length === 0) {
			container.appendChild(E('p', {}, [ _('No managed users found.') ]));
			return;
		}

		const table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, [ _('Username') ]),
				E('th', { 'class': 'th' }, [ _('UID') ]),
				E('th', { 'class': 'th' }, [ _('GID') ]),
				E('th', { 'class': 'th' }, [ _('Backend') ]),
				E('th', { 'class': 'th cbi-section-actions' }, [ _('Actions') ])
			])
		]);

		users.forEach(u => {
			const backends = [];
			if (u.in_samba4) backends.push('Samba4');
			if (u.in_ksmbd)  backends.push('ksmbd');
			const row = E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'data-title': _('Username') }, [ u.username ]),
				E('td', { 'class': 'td', 'data-title': _('UID') }, [ u.uid != null ? String(u.uid) : '—' ]),
				E('td', { 'class': 'td', 'data-title': _('GID') }, [ u.gid != null ? String(u.gid) : '—' ]),
				E('td', { 'class': 'td', 'data-title': _('Backend') }, [ backends.join(', ') || '—' ]),
				E('td', { 'class': 'td cbi-section-actions' }, [
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, 'handleChangePassword', u.username)
					}, [ _('Password') ]),
					' ',
					E('button', {
						'class': 'cbi-button cbi-button-negative',
						'click': ui.createHandlerFn(this, 'handleRemoveUser', u.username)
					}, [ _('Remove') ])
				])
			]);
			table.appendChild(row);
		});

		container.appendChild(table);
	},

	handleAddUser: function() {
		const username  = (document.getElementById('su-username').value || '').trim();
		const password  = document.getElementById('su-password').value || '';
		const password2 = document.getElementById('su-password2').value || '';

		if (!username) {
			ui.addNotification(null, E('p', {}, [ _('Username is required') ]), 'error');
			return;
		}
		if (!password) {
			ui.addNotification(null, E('p', {}, [ _('Password is required') ]), 'error');
			return;
		}
		if (password !== password2) {
			ui.addNotification(null, E('p', {}, [ _('Passwords do not match') ]), 'error');
			return;
		}

		return callAddUser(username, password).then(res => {
			if (res && res.success) {
				ui.addNotification(null, E('p', {}, [
					_('User "%s" created (UID %s, backend %s)').format(res.username, res.uid, res.backend || '')
				]), 'info');
				document.getElementById('su-username').value = '';
				document.getElementById('su-password').value = '';
				document.getElementById('su-password2').value = '';
				return this.refreshTable();
			}
			ui.addNotification(null, E('p', {}, [
				(res && res.error) ? res.error : _('Failed to create user (no error detail from RPC)')
			]), 'error');
		}).catch(err => {
			ui.addNotification(null, E('p', {}, [
				_('RPC error: %s — log out of LuCI and log back in, then retry').format(err.message || err)
			]), 'error');
		});
	},

	handleRemoveUser: function(username) {
		return ui.showModal(_('Confirm removal'), [
			E('p', {}, [ _('Really remove user "%s"? This deletes the system account and the SMB password entry.').format(username) ]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ _('Cancel') ]),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-negative',
					'click': ui.createHandlerFn(this, function() {
						ui.hideModal();
						return callRemoveUser(username).then(res => {
							if (res && res.success) {
								ui.addNotification(null, E('p', {}, [ _('User "%s" removed').format(username) ]), 'info');
								return this.refreshTable();
							}
							ui.addNotification(null, E('p', {}, [ (res && res.error) || _('Failed to remove user') ]), 'error');
						}).catch(err => {
							ui.addNotification(null, E('p', {}, [ _('RPC error: %s').format(err.message || err) ]), 'error');
						});
					})
				}, [ _('Remove') ])
			])
		]);
	},

	handleChangePassword: function(username) {
		const pwd1 = E('input', { 'type': 'password', 'class': 'cbi-input-password', 'style': 'width:100%', 'autocomplete': 'new-password' });
		const pwd2 = E('input', { 'type': 'password', 'class': 'cbi-input-password', 'style': 'width:100%', 'autocomplete': 'new-password' });

		return ui.showModal(_('Change password for "%s"').format(username), [
			E('div', { 'class': 'cbi-value' }, [ E('label', {}, [ _('New password') ]), pwd1 ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', {}, [ _('Confirm password') ]), pwd2 ]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ _('Cancel') ]),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-positive',
					'click': ui.createHandlerFn(this, function() {
						const p1 = pwd1.value || '';
						const p2 = pwd2.value || '';
						if (!p1) {
							ui.addNotification(null, E('p', {}, [ _('Password is required') ]), 'error');
							return;
						}
						if (p1 !== p2) {
							ui.addNotification(null, E('p', {}, [ _('Passwords do not match') ]), 'error');
							return;
						}
						ui.hideModal();
						return callChangePassword(username, p1).then(res => {
							if (res && res.success)
								ui.addNotification(null, E('p', {}, [ _('Password for "%s" updated').format(username) ]), 'info');
							else
								ui.addNotification(null, E('p', {}, [ (res && res.error) || _('Failed to change password') ]), 'error');
						}).catch(err => {
							ui.addNotification(null, E('p', {}, [ _('RPC error: %s').format(err.message || err) ]), 'error');
						});
					})
				}, [ _('Change') ])
			])
		]);
	},

	refreshTable: function() {
		return callListUsers().then(res => {
			this.renderUserTable((res && res.users) || []);
		}).catch(() => {
			this.renderUserTable([]);
		});
	}
});
