import Foundation

public enum VideoWorkflow: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case proRes4K422
    case proRes6K422
    case proRes8KRaw

    public var id: String { rawValue }

    /// Conservative approximate storage throughput for one stream, in MB/s.
    /// Codec, frame rate, and project settings can materially vary the need.
    public var estimatedRequiredMBps: Double {
        switch self {
        case .proRes4K422: 95
        case .proRes6K422: 220
        case .proRes8KRaw: 700
        }
    }
}

public enum VideoCapabilityStatus: String, Codable, Hashable, Sendable {
    case supported
    case marginal
    case notRecommended
}

public struct VideoWorkflowCapability: Codable, Hashable, Sendable {
    public let workflow: VideoWorkflow
    public let status: VideoCapabilityStatus
    public let estimatedRequiredMBps: Double

    public init(workflow: VideoWorkflow, status: VideoCapabilityStatus, estimatedRequiredMBps: Double) {
        self.workflow = workflow
        self.status = status
        self.estimatedRequiredMBps = estimatedRequiredMBps
    }
}

public struct VideoCapabilityAssessment: Codable, Hashable, Sendable {
    public let measuredWriteMBps: Double
    public let capabilities: [VideoWorkflowCapability]
    public let maximum4KStreams: Int

    public init(measuredWriteMBps: Double, capabilities: [VideoWorkflowCapability], maximum4KStreams: Int) {
        self.measuredWriteMBps = measuredWriteMBps
        self.capabilities = capabilities
        self.maximum4KStreams = maximum4KStreams
    }

    public func capability(for workflow: VideoWorkflow) -> VideoWorkflowCapability {
        capabilities.first(where: { $0.workflow == workflow })!
    }
}

public enum VideoCapabilityEstimator {
    public static func assess(sustainedWriteMBps: Double) -> VideoCapabilityAssessment {
        let writeMBps = max(0, sustainedWriteMBps)
        let capabilities = VideoWorkflow.allCases.map { workflow in
            let ratio = writeMBps / workflow.estimatedRequiredMBps
            let status: VideoCapabilityStatus
            switch ratio {
            case 1...: status = .supported
            case 0.75...: status = .marginal
            default: status = .notRecommended
            }
            return VideoWorkflowCapability(
                workflow: workflow,
                status: status,
                estimatedRequiredMBps: workflow.estimatedRequiredMBps
            )
        }
        return VideoCapabilityAssessment(
            measuredWriteMBps: writeMBps,
            capabilities: capabilities,
            maximum4KStreams: Int(writeMBps / VideoWorkflow.proRes4K422.estimatedRequiredMBps)
        )
    }
}
