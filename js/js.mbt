///|
/// An opaque host value (request, response, blob, ...). Only the adapters in
/// `app`, `bridge` and `worker` look inside it.
#external
pub type Value

///|
pub extern "js" fn now() -> Double = "() => Date.now()"

///|
pub extern "js" fn set_timeout(f : () -> Unit, ms : Int) -> Unit = "(f, ms) => { setTimeout(f, ms) }"

///|
/// Random, URL-safe operation id.
pub extern "js" fn random_id() -> String = "() => globalThis.crypto.randomUUID()"

///|
pub extern "js" fn log(message : String) -> Unit = "(m) => console.log(m)"

///|
pub extern "js" fn warn(message : String) -> Unit = "(m) => console.warn(m)"

///|
/// Serialize a header list for the host `Headers` constructor.
pub fn headers_json(headers : Array[(String, String)]) -> String {
  Json::array(
    headers.map(fn(pair) {
      Json::array([Json::string(pair.0), Json::string(pair.1)])
    }),
  ).stringify()
}
