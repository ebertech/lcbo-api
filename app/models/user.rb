class User < ActiveRecord::Base
  SESSION_TTL = 3.weeks
  EMAIL_RE = /\A[^@]+@[^@]+\Z/

  has_many :keys, dependent: :destroy

  before_create :generate_verification_token
  after_create  :deliver_welcome_message
  before_save   :encrypt_password,      if: :password_changed?
  after_update  :verify_email_address,  if: :email_changed?

  validates :password,
    presence: true,
    length: { minimum: 6, maximum: 200 },
    if: :password_changed?

  validates :email,
    format: {
      with: EMAIL_RE,
      message: I18n.t('user.invalid_email')
    },
    length: { minimum: 6, maximum: 200 },
    if: :email_changed?

  validates :name, presence: true

  def self.challenge(params)
    email    = params[:email].to_s.downcase
    password = params[:password]

    return if email.blank? || password.blank?

    if (found = where('email IS NOT NULL AND LOWER(email) = ?', email).first)
      return if (password_digest = found.password_digest).blank?
      password_digest == password
    else
      nil
    end
  end

  def self.lookup(raw_token)
    return unless token = Token.parse(raw_token)

    if token.session?
      lookup_session_token(token)
    elsif token.auth?
      lookup_auth_token(token)
    elsif token.verification?
      lookup_verificaiton_token(token)
    end
  end

  def self.lookup_auth_token(token)
    id = Base62.uuid_decode(token.key)
    return unless user = where(id: id).first

    if SecureCompare.compare(user.auth_token, token.secret)
      user
    else
      nil
    end
  end

  def self.lookup_session_token(token)
    return unless json = $redis.get("sessions:#{token.key}")

    payload = JSON.parse(json)

    if SecureCompare.compare(token.secret, json['secret'])
      where(id: json['user_id']).first
    else
      nil
    end
  end

  def self.lookup_verification_token(token)
    id = Base62.uuid_decode(token.key)
    return unless user = where(id: id).first

    if SecureCompare.compare(user.verification_token, token.secret)
      user.update_attribute(:verification_token, nil)
      user
    else
      nil
    end
  end

  def id62
    Base62.uuid_encode(id)
  end

  def password_changed?
    @password_changed ? true : false
  end

  def password=(val)
    @password_changed = true
    @password = val
  end

  def password
    @password
  end

  def password_digest
    BCrypt::Password.new(read_attribute(:password_digest))
  end

  def email_changed?
    @email_changed ? true : false
  end

  def email=(val)
    @email_changed = true
    @email = val
    write_attribute :new_email, val
    generate_verification_token
  end

  def generate_auth_token
    self.auth_token = Token.generate(:auth).secret
  end

  def generate_verification_token
    self.verification_token = Token.generate(:verification).secret
  end

  def verification_token
    Token.new(id62, read_attribute(:verification_token), :verification).to_s
  end

  def auth_token
    Token.new(id62, read_attribute(:auth_token), :auth).to_s
  end

  def generate_session_token
    token = Token.generate(:session)
    json = %|{"user_id":"#{id}","secret":"#{token.secret}"}|
    $redis.setex("sessions:#{token.key}", SESSION_TTL, json)
    token
  end

  private

  def set_password_digest
    return true unless password_changed?
    self.password_digest = BCrypt::Password.create(password)
  end

  def deliver_welcome_message
    UserMailer.welcome_message(id).deliver
    true
  end
end
