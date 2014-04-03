Model = require './Model'
auth = require '../auth'
db = require '../db'
_ = require 'underscore'

module.exports = class Account extends Model
  @create: (data) ->
    new Account data

  @register: (username, email, passwd, callback = null) ->
    passwd_salt = auth.randomSalt()

    @insert
      username: username
      passwd: auth.hashPasswd(passwd, passwd_salt)
      passwd_salt: passwd_salt
      email: email
      signup: new Date()
      group: []
      setting: {}
      attribure: {}
      tokens: []
     , callback

  # @param callback(token)
  createToken: (attribute, callback) ->
    # @param callback(token)
    generateToken = (callback) ->
      token = auth.randomSalt()

      Account.findOne
        'tokens.token': token
      , (result) ->
        if result
          generateToken callback
        else
          callback token

    generateToken (token) =>
      @update
        $push:
          tokens:
            token: token
            available: true
            created_at: new Date()
            updated_at: new Date()
            attribute: attribute
      , ->
        callback token

  removeToken: (token, callback = null) ->
    @update
      $pull:
        tokens:
          token: token
    , ->
      callback() if callback

  # @param callback(User)
  @authenticate: (token, callback) ->
    unless token
      callback null

    Account.findOne
      'tokens.token': token
    , (result) ->
      if result
        callback result
      else
        callback null

  # @return bool
  matchPasswd: (passwd) ->
    auth.hashPasswd(passwd, @data.passwd_salt) is @data.passwd

  inGroup: (group) ->
    return group in @data.group

  @byUsername: (username, callback) ->
    @findOne
      username: username
    , (result) ->
      callback result

  @byEmail: (email, callback) ->
    @findOne
      email: email
    , (result) ->
      callback result

  @byUsernameOrEmail: (username, callback) ->
    Account.byUsername username, (account) ->
      if account
        return callback account

      Account.byEmail username, (account) ->
        return callback account