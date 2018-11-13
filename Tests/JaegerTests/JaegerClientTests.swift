//
//  JaegerClientTests.swift
//  JaegerTests
//
//  Created by Simon-Pierre Roy on 11/8/18.
//

import XCTest
@testable import Jaeger
import CoreData

class JaegerClientTests: XCTestCase {

    private func newStack() -> CoreDataStack {
        let stack = CoreDataStack(
            modelName: TestUtilities.Constants.coreDataAgentModelName,
            model: TestUtilities.modelForCoreDataAgent,
            type: .inMemory
        )

        return stack
    }

    private func newTracer(session: URLSession, savingInterval: Double, sendingInterval: Double) -> JaegerTracer? {

        let reachability = TestReachabilityTracker(reachability: true)
        guard let endPoint = URL(string: "testURL") else { return nil }
        let sender = JSONSender(endPoint: endPoint, session: session)

        guard let config = CoreDataAgentConfiguration(
            averageMaximumSpansPerSecond: 100,
            savingInterval: savingInterval ,
            sendingInterval: sendingInterval,
            errorDelegate: nil,
            coreDataFolderURL: nil
            ) else {
                return nil
        }

        let cdAgent = CoreDataAgent<JaegerSpan>(
            config: config,
            sender: sender,
            stack: newStack(),
            reachabilityTracker: reachability
        )

        let tracer = JaegerTracer(agent: cdAgent)

        return tracer
    }

    func testJaegerClientTrace() {

        let spanSent = expectation(description: "span sent")
        let session = URLSessionMock()

        var httpData: Data?
        session.dataTaskExcuted = { request in
            httpData = request.httpBody
            spanSent.fulfill()
        }

        guard let tracer = newTracer(
            session: session,
            savingInterval: 0.10,
            sendingInterval: 0.25
            ) else {
            return XCTFail("Invalid CDAgentConfig")
        }

        // TEST
        let span1 = tracer.startRootSpan(operationName: "TestSpan1")
        let span2 = tracer.startSpan(operationName: "TestSpan2", childOf: span1.spanRef)

        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.07) {
            span1.finish()
        }

        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.13) {
            let tag = Tag(key: "TestTag", tagType: .bool(true))
            span2.set { $0.set(tag: tag) }
            span2.finish()
        }

        wait(for: [spanSent], timeout: 1)

        guard let data = httpData  else {
            return XCTFail("Spans need to be included in the URLRequest")
        }

        let spans = try? JSONDecoder().decode([JaegerSpan].self, from: data)
        XCTAssertEqual(spans?.count, 2)

        guard let jaegerSpan1 = spans?.first else { return XCTFail("Expecting 2 spans!") }
        guard let jaegerSpan2 = spans?.last else { return XCTFail("Expecting 2 spans!") }

        XCTAssertEqual(jaegerSpan1.operationName, "TestSpan1")
        XCTAssertEqual(jaegerSpan2.operationName, "TestSpan2")
        XCTAssertEqual(jaegerSpan2.parentSpanId, jaegerSpan1.spanId)
        XCTAssertEqual(jaegerSpan1.parentSpanId, 0)
        XCTAssertEqual(jaegerSpan1.traceIdLow, jaegerSpan2.traceIdLow)
        XCTAssertEqual(jaegerSpan1.traceIdHigh, jaegerSpan2.traceIdHigh)
        XCTAssertEqual(jaegerSpan2.tags?.first?.key, "TestTag")
        XCTAssertEqual(jaegerSpan2.tags?.first?.vBool, true)

        XCTAssertGreaterThan(jaegerSpan1.duration, 70000) // 0.07s to 0.14s
        XCTAssertLessThan(jaegerSpan1.duration, 140000)

        XCTAssertGreaterThan(jaegerSpan2.duration, 130000) // 0.13s to 0.26s
        XCTAssertLessThan(jaegerSpan2.duration, 260000)
    }
}