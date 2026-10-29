import Foundation
import Darwin
import Security

let helperSocketPath = "/var/run/local.lidawake.helper.sock"
let helperLabel = "local.lidawake.helper"
struct ServiceRequest: Codable { let command: String }
struct ServiceReply: Codable {
    let state: String
    let message: String?
    let version: Int
    init(_ state: String, message: String? = nil) { self.state = state; self.message = message; version = 2 }
}
func socketAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { throw AwakeError.message("通信路径过长。") }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size); address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
        destination.copyBytes(from: path.utf8); destination[path.utf8.count] = 0
    }
    return address
}
func configureSocket(_ fd: Int32) {
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    var timeout = timeval(tv_sec: 6, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var noSignal: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
}
func sendPacket<T: Encodable>(_ packet: T, to fd: Int32) throws {
    var bytes = Array(try JSONEncoder().encode(packet)); bytes.append(10)
    try bytes.withUnsafeBytes { data in
        var count = 0
        while count < data.count {
            let sent = Darwin.write(fd, data.baseAddress!.advanced(by: count), data.count - count)
            if sent < 0 && errno == EINTR { continue }
            guard sent > 0 else { throw AwakeError.message("辅助服务连接已断开。") }
            count += sent
        }
    }
}
func receivePacket<T: Decodable>(_ type: T.Type, from fd: Int32) throws -> T {
    var data = Data(); var byte: UInt8 = 0
    while data.count < 4096 {
        let count = Darwin.read(fd, &byte, 1)
        if count < 0 && errno == EINTR { continue }
        guard count == 1 else { throw AwakeError.message("辅助服务没有响应，请重新打开应用。") }
        if byte == 10 { return try JSONDecoder().decode(type, from: data) }
        data.append(byte)
    }
    throw AwakeError.message("辅助服务消息无效。")
}
func peerAuditToken(_ fd: Int32) throws -> audit_token_t {
    var token = audit_token_t(); var size = socklen_t(MemoryLayout<audit_token_t>.size)
    guard getsockopt(fd, 0, LOCAL_PEERTOKEN, &token, &size) == 0,
          size == MemoryLayout<audit_token_t>.size else { throw AwakeError.message("无法验证调用进程。") }
    return token
}
func verifiedPeer(_ fd: Int32, requirement: SecRequirement) throws -> SessionOwner {
    var uid: uid_t = 0; var gid: gid_t = 0
    guard getpeereid(fd, &uid, &gid) == 0, uid >= 500 else { throw AwakeError.message("调用用户无效。") }
    var token = try peerAuditToken(fd)
    let data = withUnsafeBytes(of: &token) { Data($0) }
    var code: SecCode?
    let attributes = [kSecGuestAttributeAudit as String: data] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code,
          SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { throw AwakeError.message("只允许已安装的合盖不眠应用调用此服务。") }
    // audit_token_t is specified by libbsm: [auid, euid, egid, ruid, rgid, pid, asid, pidversion].
    let words = withUnsafeBytes(of: &token) { Array($0.bindMemory(to: UInt32.self)) }
    let pid = Int32(bitPattern: words[5])
    guard words[1] == uid, let identity = ProcessIdentity.read(pid), identity.uid == uid else {
        throw AwakeError.message("调用进程已退出。")
    }
    return SessionOwner(uid: uid, pid: pid, stamp: identity.stamp)
}
final class ServiceClient {
    func request(_ command: String) throws -> ServiceReply {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AwakeError.message("无法连接辅助服务。") }
        defer { close(fd) }; configureSocket(fd)
        var address = try socketAddress(helperSocketPath)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw AwakeError.message("需要安装辅助服务。") }
        var uid: uid_t = 1; var gid: gid_t = 1
        guard getpeereid(fd, &uid, &gid) == 0, uid == 0 else { throw AwakeError.message("辅助服务身份无效。") }
        try sendPacket(ServiceRequest(command: command), to: fd)
        let reply = try receivePacket(ServiceReply.self, from: fd)
        guard reply.version == 2 else { throw AwakeError.message("请重新安装新版辅助服务。") }
        if reply.state == "error" { throw AwakeError.message(reply.message ?? "操作失败。") }
        return reply
    }
}
