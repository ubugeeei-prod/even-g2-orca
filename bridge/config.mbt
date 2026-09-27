///|
let version : String = "0.1.0"

///|
let mac_cli : String = "/Applications/Orca.app/Contents/Resources/app.asar.unpacked/out/cli/index.js"

///|
struct Config {
  host : String
  port : Int
  token : String
  public_url : String
  allowed_origins : String
  web_root : String
  cli : String
  runtime_file : String
  whisper_cli : String
  whisper_model : String
  whisper_language : String
}

///|
fn or_default(value : String, fallback : String) -> String {
  if value == "" {
    fallback
  } else {
    value
  }
}

///|
fn parse_port(value : String, fallback : Int) -> Int {
  if value == "" {
    return fallback
  }
  let mut port = 0
  for c in value {
    if !(c is ('0'..='9')) || port > 65535 {
      return fallback
    }
    port = port * 10 + (c.to_int() - '0'.to_int())
  }
  if port < 1 || port > 65535 {
    fallback
  } else {
    port
  }
}

///|
/// Where Orca keeps `orca-runtime.json` for the signed-in user.
fn orca_user_data() -> String {
  let configured = env("ORCA_USER_DATA_PATH")
  if configured != "" {
    return configured
  }
  if platform() == "darwin" {
    join_path(home_dir(), "Library/Application Support/orca")
  } else {
    join_path(
      or_default(env("XDG_CONFIG_HOME"), join_path(home_dir(), ".config")),
      "orca",
    )
  }
}

///|
/// Private per-user state (the pairing token), independent of the cwd.
fn state_dir() -> String {
  let configured = env("BRIDGE_STATE_DIR")
  if configured != "" {
    return configured
  }
  if platform() == "darwin" {
    join_path(home_dir(), "Library/Application Support/even-g2-orca")
  } else {
    join_path(
      or_default(env("XDG_STATE_HOME"), join_path(home_dir(), ".local/state")),
      "even-g2-orca",
    )
  }
}

///|
fn load_config() -> Config {
  let configured_token = env("BRIDGE_TOKEN")
  let token = if configured_token != "" {
    configured_token
  } else {
    load_or_create_token(join_path(state_dir(), "bridge-token"))
  }
  if token.length() < @core.MIN_TOKEN_CHARS {
    @js.warn(
      "BRIDGE_TOKEN は \{@core.MIN_TOKEN_CHARS} 文字以上にしてください。",
    )
    exit(1)
  }
  let cli = match env("ORCA_CLI_PATH") {
    "" => if file_exists(mac_cli) { mac_cli } else { "orca" }
    path => path
  }
  {
    host: or_default(env("BRIDGE_HOST"), "127.0.0.1"),
    port: parse_port(env("BRIDGE_PORT"), 3210),
    token,
    public_url: env("BRIDGE_PUBLIC_URL"),
    allowed_origins: env("BRIDGE_ALLOWED_ORIGINS"),
    web_root: or_default(
      env("ORCA_WEB_ROOT"),
      join_path(script_dir(), "../web"),
    ),
    cli,
    runtime_file: join_path(orca_user_data(), "orca-runtime.json"),
    whisper_cli: env("WHISPER_CLI_PATH"),
    whisper_model: env("WHISPER_MODEL_PATH"),
    whisper_language: or_default(env("WHISPER_LANGUAGE"), "ja"),
  }
}

///|
fn Config::speech(self : Config) -> Bool {
  self.whisper_cli != "" && self.whisper_model != ""
}
