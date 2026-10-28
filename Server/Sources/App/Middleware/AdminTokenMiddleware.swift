import Vapor

struct AdminTokenMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let expected = Environment.get("ADMIN_TOKEN"), !expected.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "ADMIN_TOKEN nu este configurat pe server.")
        }
        guard let provided = request.headers.bearerAuthorization?.token,
              constantTimeEquals(provided, expected)
        else {
            throw Abort(.unauthorized)
        }
        return try await next.respond(to: request)
    }

    private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
