public struct SessionSnapshot: Equatable, Sendable {
    public let session: Session
    public let state: SessionState
    public init(session: Session, state: SessionState) {
        self.session = session; self.state = state
    }
}
