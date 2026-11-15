// Sends a command to a running Debug build of OldMacDoc (see docs/TESTING.md), e.g. "hold on".
import Foundation

DistributedNotificationCenter.default().postNotificationName(
    .init("com.kewonit.oldmacdoc.debug"), object: CommandLine.arguments.dropFirst().joined(separator: " "),
    userInfo: nil, deliverImmediately: true)
