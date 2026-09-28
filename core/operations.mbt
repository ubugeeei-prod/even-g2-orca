///|
priv enum OpState {
  Pending
  Finished(Int, String)
}

///|
priv struct OpEntry {
  fingerprint : String
  at : Double
  mut state : OpState
}

///|
/// Remembers recent operation ids so a retried request never delivers the
/// same prompt twice. Held in bridge memory only; not durable across restarts.
pub struct OperationLog {
  priv entries : Map[String, OpEntry]
}

///|
pub fn OperationLog::new() -> OperationLog {
  { entries: {}, }
}

///|
pub(all) enum Begin {
  /// First sighting: perform the effect, then call `finish`.
  Fresh
  /// Same id and payload already completed: replay the stored response.
  Replay(Int, String)
  /// Same id still executing.
  InFlight
  /// Same id reused for a different payload.
  Conflict
} derive(Eq, Debug)

///|
pub extend Begin with Eq::{not_equal, equal}

///|
pub extend Begin with Debug::{to_repr}

///|
pub fn OperationLog::begin(
  self : OperationLog,
  id : String,
  fingerprint : String,
  now : Double,
) -> Begin {
  self.prune(now)
  match self.entries.get(id) {
    Some(entry) if entry.fingerprint != fingerprint => Conflict
    Some({ state: Pending, .. }) => InFlight
    Some({ state: Finished(status, body), .. }) => Replay(status, body)
    None => {
      self.entries[id] = { fingerprint, at: now, state: Pending, }
      Fresh
    }
  }
}

///|
pub fn OperationLog::finish(
  self : OperationLog,
  id : String,
  status : Int,
  body : String,
) -> Unit {
  if self.entries.get(id) is Some(entry) {
    entry.state = Finished(status, body)
  }
}

///|
/// Forget an operation that failed before anything was delivered, so the
/// same id may be retried.
pub fn OperationLog::forget(self : OperationLog, id : String) -> Unit {
  self.entries.remove(id)
}

///|
pub fn OperationLog::length(self : OperationLog) -> Int {
  self.entries.length()
}

///|
fn OperationLog::prune(self : OperationLog, now : Double) -> Unit {
  let expired : Array[String] = []
  for id, entry in self.entries {
    if now - entry.at > OPERATION_RETENTION_MS {
      expired.push(id)
    }
  }
  for id in expired {
    self.entries.remove(id)
  }
  // Insertion order is age order; drop the oldest beyond the cap.
  let excess = self.entries.length() - MAX_OPERATIONS + 1
  if excess > 0 {
    let oldest : Array[String] = []
    for id, _ in self.entries {
      if oldest.length() >= excess {
        break
      }
      oldest.push(id)
    }
    for id in oldest {
      self.entries.remove(id)
    }
  }
}
