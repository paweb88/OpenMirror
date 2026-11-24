import XCTest
@testable import OpenMirror

final class GestureMapperTests: XCTestCase {
    private let size = ScreenSize(width: 440, height: 956)

    func testQuickClickIsTap() {
        let gesture = GestureMapper.gesture(start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5),
                                            heldSeconds: 0.1, delayBeforeMove: nil, size: size)
        XCTAssertEqual(gesture, .tap(x: 220, y: 478))
    }

    func testLongStillPressIsHold() {
        let gesture = GestureMapper.gesture(start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.1, y: 0.1),
                                            heldSeconds: 1.2, delayBeforeMove: nil, size: size)
        XCTAssertEqual(gesture, .hold(x: 44, y: 96, seconds: 1.2))
    }

    func testFastMoveIsQuickSwipe() {
        let gesture = GestureMapper.gesture(start: CGPoint(x: 0.9, y: 0.5), end: CGPoint(x: 0.1, y: 0.5),
                                            heldSeconds: 0.2, delayBeforeMove: 0.02, size: size)
        XCTAssertEqual(gesture, .drag(fromX: 396, fromY: 478, toX: 44, toY: 478, pressSeconds: 0.05))
    }

    func testPauseBeforeMoveIsLongPressDrag() {
        let gesture = GestureMapper.gesture(start: CGPoint(x: 0.2, y: 0.2), end: CGPoint(x: 0.6, y: 0.6),
                                            heldSeconds: 2, delayBeforeMove: 0.8, size: size)
        guard case let .drag(_, _, _, _, press) = gesture else { return XCTFail("expected drag") }
        XCTAssertEqual(press, 0.6)
    }

    func testCoordinatesAreClamped() {
        let point = GestureMapper.toPoints(CGPoint(x: -0.2, y: 1.4), in: size)
        XCTAssertEqual(point.x, 0)
        XCTAssertEqual(point.y, 956)
    }

    func testTinyScrollIsIgnored() {
        XCTAssertNil(GestureMapper.scrollSwipe(at: CGPoint(x: 0.5, y: 0.5),
                                               normalizedDelta: CGVector(dx: 0.001, dy: 0), size: size))
    }

    func testScrollFollowsFingers() {
        let swipe = GestureMapper.scrollSwipe(at: CGPoint(x: 0.5, y: 0.5),
                                              normalizedDelta: CGVector(dx: -0.5, dy: 0), size: size)
        XCTAssertEqual(swipe, .drag(fromX: 220, fromY: 478, toX: 0, toY: 478, pressSeconds: 0.05))
    }

    func testKeyMapping() {
        XCTAssertEqual(GestureMapper.text(forKeyCode: 51, characters: nil), "\u{8}")
        XCTAssertEqual(GestureMapper.text(forKeyCode: 36, characters: "\r"), "\n")
        XCTAssertEqual(GestureMapper.text(forKeyCode: 0, characters: "ą"), "ą")
        XCTAssertNil(GestureMapper.text(forKeyCode: 123, characters: "\u{F702}"))  // arrow key
    }
}

final class MJPEGParserTests: XCTestCase {
    private let frameA = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
    private let frameB = Data([0xFF, 0xD8, 0x03, 0xFF, 0xD9])

    func testExtractsFrameFromMultipartChunk() {
        var parser = MJPEGParser()
        let chunk = Data("--Boundary\r\nContent-type: image/jpeg\r\n\r\n".utf8) + frameA + Data("\r\n".utf8)
        XCTAssertEqual(parser.append(chunk), frameA)
    }

    func testFrameSplitAcrossChunks() {
        var parser = MJPEGParser()
        XCTAssertNil(parser.append(frameA.prefix(3)))
        XCTAssertEqual(parser.append(frameA.suffix(3)), frameA)
    }

    func testReturnsNewestOfSeveralFrames() {
        var parser = MJPEGParser()
        XCTAssertEqual(parser.append(frameA + frameB), frameB)
    }
}

final class UsbmuxPacketTests: XCTestCase {
    func testHeaderRoundTrip() throws {
        let packet = try UsbmuxPacket.encode(["MessageType": "ListDevices"], tag: 7)
        XCTAssertEqual(try UsbmuxPacket.length(fromHeader: packet), packet.count)
        XCTAssertEqual(packet[4], 1)   // version
        XCTAssertEqual(packet[8], 8)   // plist message
        XCTAssertEqual(packet[12], 7)  // tag
        let body = try UsbmuxPacket.decodeBody(packet.subdata(in: 16..<packet.count))
        XCTAssertEqual(body["MessageType"] as? String, "ListDevices")
    }

    func testRejectsBogusLength() {
        XCTAssertThrowsError(try UsbmuxPacket.length(fromHeader: Data(repeating: 0, count: 16)))
    }

    func testPortIsNetworkByteOrder() {
        XCTAssertEqual(UsbmuxPacket.portNumber(8100), 0xA41F)
    }

    func testParsesDeviceList() {
        let reply: [String: Any] = ["DeviceList": [
            ["DeviceID": 3, "Properties": ["SerialNumber": "ABC", "ConnectionType": "USB"]],
            ["DeviceID": 4, "Properties": ["ConnectionType": "Network"]],
        ]]
        XCTAssertEqual(UsbmuxPacket.devices(from: reply), [UsbmuxDevice(deviceID: 3, udid: "ABC", connectionType: "USB")])
    }
}

final class SigningAndLogTests: XCTestCase {
    func testTeamIDValidation() {
        XCTAssertTrue(SigningTeams.isValidTeamID("AB12CD34EF"))
        XCTAssertFalse(SigningTeams.isValidTeamID("ab12cd34ef"))
        XCTAssertFalse(SigningTeams.isValidTeamID("SHORT"))
    }

    func testRecognisesDevelopmentCertificates() {
        XCTAssertTrue(SigningTeams.isDevelopmentCertificate("Apple Development: Jane (XYZ)"))
        XCTAssertFalse(SigningTeams.isDevelopmentCertificate("Developer ID Application: Jane"))
    }

    func testLogEvents() {
        if case .serverStarted? = WDALogInterpreter.event(for: "ServerURLHere->http://1.2.3.4:8100<-ServerURLHere") {} else {
            XCTFail("expected serverStarted")
        }
        if case .needsUnlock? = WDALogInterpreter.event(for: "Unlock iPhone to Continue") {} else {
            XCTFail("expected needsUnlock")
        }
        XCTAssertNil(WDALogInterpreter.event(for: "Test Suite started"))
    }

    func testBundleIDIsPerTeam() {
        XCTAssertEqual(WDARunner.bundleID(teamID: "AB12CD34EF"), "io.github.openmirror.wda.ab12cd34ef")
    }
}

@MainActor
final class ComposeTests: XCTestCase {
    func testPrintableKeyStartsComposing() {
        let model = MirrorModel()
        model.handleKey("a")
        model.handleKey("ą")
        XCTAssertTrue(model.isComposing)
        XCTAssertEqual(model.composeText, "aą")
    }

    func testBackspaceWithoutComposeGoesToPhone() {
        let model = MirrorModel()
        model.handleKey("\u{8}")
        XCTAssertFalse(model.isComposing)
        XCTAssertEqual(model.composeText, "")
    }

    func testCancelClearsText() {
        let model = MirrorModel()
        model.handleKey("x")
        model.cancelComposing()
        XCTAssertFalse(model.isComposing)
        XCTAssertEqual(model.composeText, "")
    }
}

final class ScreenCaptureTests: XCTestCase {
    func testMatchesUDIDWithOrWithoutDashes() {
        XCTAssertTrue(ScreenCapture.matches(uniqueID: "00001111222233334444AAAA", udid: "00001111-222233334444AAAA"))
        XCTAssertTrue(ScreenCapture.matches(uniqueID: "00001111-222233334444aaaa", udid: "00001111-222233334444AAAA"))
        XCTAssertFalse(ScreenCapture.matches(uniqueID: "FaceTime HD Camera", udid: "00001111-222233334444AAAA"))
    }

    func testChoosesIOSDeviceWhenMacAssignsItsOwnUUID() {
        let candidates = [(uniqueID: "0x1100000000001", modelID: "UVC Camera"),
                          (uniqueID: "1A2B3C4D-0000-4000-8000-000000000001", modelID: "iOS Device")]
        XCTAssertEqual(ScreenCapture.chooseDevice(candidates, udid: "00001111-222233334444AAAA"), 1)
    }

    func testIgnoresRegularCameras() {
        XCTAssertNil(ScreenCapture.chooseDevice([(uniqueID: "cam", modelID: "UVC Camera")], udid: "X"))
    }
}
