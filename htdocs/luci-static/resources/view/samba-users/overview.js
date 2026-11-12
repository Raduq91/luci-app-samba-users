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

function buildUserTable(users, view) {
	if (!users || users.length === 0) {
		return E('p', { 'id': 'su-user-list' }, [ _('No managed users found.') ]);
	}

	const table = E('table', { 'class': 'table', 'id': 'su-user-list' }, [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, [ _('Username') ]),
			E('th', { 'class': 'th' }, [ _('UID') ]),
			E('th', { 'class': 'th' }, [ _('GID') ]),
			E('th', { 'class': 'th' }, [ _('Backend') ]),
			E('th', { 'class': 'th cbi-section-actions' }, [ _('Actions') ])
		])
	]);

	users.forEach(function(u) {
		const backends = [];
		if (u.in_samba4) backends.push('Samba4');
		if (u.in_ksmbd)  backends.push('ksmbd');
		table.appendChild(E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, [ u.username || '' ]),
			E('td', { 'class': 'td' }, [ u.uid != null ? String(u.uid) : '—' ]),
			E('td', { 'class': 'td' }, [ u.gid != null ? String(u.gid) : '—' ]),
			E('td', { 'class': 'td' }, [ backends.join(', ') || '—' ]),
			E('td', { 'class': 'td cbi-section-actions' }, [
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': ui.createHandlerFn(view, 'handleChangePassword', u.username)
				}, [ _('Password') ]),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-negative',
					'click': ui.createHandlerFn(view, 'handleRemoveUser', u.username)
				}, [ _('Remove') ])
			])
		]));
	});

	return table;
}

return view.extend({
	load: function() {
		return Promise.all([
			callListUsers().catch(function(e) {
				return { _error: String(e.message || e), users: [] };
			}),
			callGetStatus().catch(function(e) {
				return { _error: String(e.message || e) };
			})
		]);
	},

	render: function(data) {
		const listRes = data[0] || {};
		const status  = data[1] || {};
		let users = [];
		if (listRes && Array.isArray(listRes.users))
			users = listRes.users;

		const body = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ _('Samba / ksmbd User Manager') ]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Create and manage share users.')
			])
		]);

		if (listRes._error) {
			body.appendChild(E('div', { 'class': 'alert-message error' }, [
				_('Failed to list users: %s').format(listRes._error)
			]));
		}

		const backendBits = [];
		if (status.ksmbd)  backendBits.push('ksmbd');
		if (status.samba4) backendBits.push('Samba4');
		if (backendBits.length)
			body.appendChild(E('div', { 'class': 'alert-message notice' }, [
				_('Active backends: %s').format(backendBits.join(', '))
			]));
		else if (!status._error)
			body.appendChild(E('div', { 'class': 'alert-message warning' }, [
				_('No SMB backend detected.')
			]));

		body.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Add user') ]),
			E('div', { 'class': 'cbi-section-node' }, [
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, [ _('Username') ]),
					E('div', { 'class': 'cbi-value-field' }, [
						E('input', {
							'type': 'text', 'id': 'su-username', 'class': 'cbi-input-text',
							'placeholder': 'myuser', 'autocomplete': 'off', 'spellcheck': 'false'
						})
					])
				]),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, [ _('Password') ]),
					E('div', { 'class': 'cbi-value-field' }, [
						E('input', {
							'type': 'password', 'id': 'su-password',
							'class': 'cbi-input-password', 'autocomplete': 'new-password'
						})
					])
				]),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, [ _('Confirm password') ]),
					E('div', { 'class': 'cbi-value-field' }, [
						E('input', {
							'type': 'password', 'id': 'su-password2',
							'class': 'cbi-input-password', 'autocomplete': 'new-password'
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

		const listSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [
				_('Existing users'),
				' ',
				E('small', {}, [ '(%d)'.format(users.length) ])
			]),
			E('div', { 'class': 'cbi-section-node', 'id': 'su-user-list-wrap' }, [
				buildUserTable(users, this)
			])
		]);
		body.appendChild(listSection);

		return body;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

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

		const self = this;
		return callAddUser(username, password).then(function(res) {
			if (res && res.success) {
				ui.addNotification(null, E('p', {}, [
					_('User "%s" created (UID %s, backend %s)').format(
						res.username, res.uid, res.backend || '')
				]), 'info');
				document.getElementById('su-username').value = '';
				document.getElementById('su-password').value = '';
				document.getElementById('su-password2').value = '';
				/* Reload the whole view so the list is rebuilt from scratch */
				return self.map ? self.map.reset() : location.reload();
			}
			ui.addNotification(null, E('p', {}, [
				(res && res.error) || _('Failed to create user')
			]), 'error');
		}).catch(function(err) {
			ui.addNotification(null, E('p', {}, [
				_('RPC error: %s').format(err.message || err)
			]), 'error');
		});
	},

	handleRemoveUser: function(username) {
		const self = this;
		return ui.showModal(_('Confirm removal'), [
			E('p', {}, [
				_('Really remove user "%s"?').format(username)
			]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ _('Cancel') ]),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-negative',
					'click': ui.createHandlerFn(this, function() {
						ui.hideModal();
						return callRemoveUser(username).then(function(res) {
							if (res && res.success) {
								ui.addNotification(null, E('p', {}, [
									_('User "%s" removed').format(username)
								]), 'info');
								location.reload();
							} else {
								ui.addNotification(null, E('p', {}, [
									(res && res.error) || _('Failed to remove user')
								]), 'error');
							}
						}).catch(function(err) {
							ui.addNotification(null, E('p', {}, [
								_('RPC error: %s').format(err.message || err)
							]), 'error');
						});
					})
				}, [ _('Remove') ])
			])
		]);
	},

	handleChangePassword: function(username) {
		const pwd1 = E('input', {
			'type': 'password', 'class': 'cbi-input-password',
			'style': 'width:100%', 'autocomplete': 'new-password'
		});
		const pwd2 = E('input', {
			'type': 'password', 'class': 'cbi-input-password',
			'style': 'width:100%', 'autocomplete': 'new-password'
		});

		return ui.showModal(_('Change password for "%s"').format(username), [
			E('div', { 'class': 'cbi-value' }, [ E('label', {}, [ _('New password') ]), pwd1 ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', {}, [ _('Confirm') ]), pwd2 ]),
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
						return callChangePassword(username, p1).then(function(res) {
							if (res && res.success)
								ui.addNotification(null, E('p', {}, [
									_('Password for "%s" updated').format(username)
								]), 'info');
							else
								ui.addNotification(null, E('p', {}, [
									(res && res.error) || _('Failed to change password')
								]), 'error');
						}).catch(function(err) {
							ui.addNotification(null, E('p', {}, [
								_('RPC error: %s').format(err.message || err)
							]), 'error');
						});
					})
				}, [ _('Change') ])
			])
		]);
	}
});
