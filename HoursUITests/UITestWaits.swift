import XCTest

// The waits that kept costing CI runs, in one place: a sheet still sliding
// away when the next tap came, a Form switch tap that was not taken, a row a
// lazy list had not made yet, and a row under the buttons that float over
// the bottom of a page. Each one only ever waits longer than a bare tap or
// `waitForExistence` would; none of them asserts anything itself, so the
// tests keep saying what they expect.

extension XCUIElement {
    /// Gone, waited for. `waitForExistence` returns at once on an element
    /// still animating away, and a tap then lands on it or on the sheet as
    /// it slides off. For helpers outside a test case (`XCUIApplication`
    /// extensions); a test calls `waitUntilGone(_:timeout:)` instead.
    @discardableResult
    func waitUntilGone(timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Swipes this element (the app, or a list) up, a bounded number of
    /// times, until `element` exists and can be hit. A lazy list only makes
    /// the rows on screen, so a row further down is not there until then.
    /// - Parameter settle: a pause after each swipe, for a recording that
    ///   should not blur.
    @discardableResult
    func scrollTo(_ element: XCUIElement, swipes: Int = 6, settle: TimeInterval = 0) -> Bool {
        for _ in 0..<swipes {
            if element.exists, element.isHittable { return true }
            swipeUp()
            if settle > 0 { Thread.sleep(forTimeInterval: settle) }
        }
        return element.exists && element.isHittable
    }

    /// Taps this element until `shows` appears: a tap that was not taken
    /// (the menu button of a page whose sheet was still closing, say) is
    /// tried again, at most `attempts` taps in all, each given `timeout` to
    /// show its result. `shows` is looked for before every new tap, so a tap
    /// that worked is never repeated.
    @discardableResult
    func tapUntil(shows: XCUIElement, attempts: Int = 3, timeout: TimeInterval = 5) -> Bool {
        for _ in 0..<attempts {
            if shows.exists { return true }
            guard waitForExistence(timeout: timeout) else { break }
            tap()
            if shows.waitForExistence(timeout: timeout) { return true }
        }
        return shows.exists
    }

    /// Taps `row` once it sits above `bar`, the buttons that float over the
    /// bottom of a list and would take the tap (a site's Write today and
    /// Sheet). Swipes this element up until then, a bounded number of times.
    /// False when the row never appeared.
    @discardableResult
    func tapAboveBottomBar(_ row: XCUIElement, bar: XCUIElement, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if row.exists, row.isHittable, !bar.exists || row.frame.maxY < bar.frame.minY - 4 { break }
            swipeUp()
        }
        guard row.exists else { return false }
        row.tap()
        return true
    }
}

extension XCTestCase {
    /// Gone, waited for: see `XCUIElement.waitUntilGone(timeout:)`. Waited
    /// on by its own waiter, so a timeout is an answer, not a failure: assert
    /// on the result where being gone is the point. Not for a test that then
    /// calls `waitForExpectations`, which would wait on this one again.
    @discardableResult
    func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        // A free-standing expectation, as the tests' own copies were: one made
        // with `expectation(for:evaluatedWith:)` belongs to the test case.
        element.waitUntilGone(timeout: timeout)
    }

    /// Swipes `container` up until `element` can be hit: see
    /// `XCUIElement.scrollTo(_:swipes:settle:)`.
    @discardableResult
    func scrollTo(_ element: XCUIElement, in container: XCUIElement, swipes: Int = 6, settle: TimeInterval = 0) -> Bool {
        container.scrollTo(element, swipes: swipes, settle: settle)
    }

    /// Taps `element` until `shows` appears: see
    /// `XCUIElement.tapUntil(shows:attempts:timeout:)`.
    @discardableResult
    func tapUntil(_ element: XCUIElement, shows: XCUIElement, attempts: Int = 3, timeout: TimeInterval = 5) -> Bool {
        element.tapUntil(shows: shows, attempts: attempts, timeout: timeout)
    }

    /// A Form switch: its own knob when it can be hit, else the trailing
    /// edge of the row where the knob is drawn. Now and then a tap on a
    /// Form switch is not taken, so when nothing happened it is tapped again
    /// on the knob's side, up to `retries` more times.
    /// - Parameter shows: what the flip brings up instead of changing the
    ///   switch at once (an explanation before turning something on).
    ///   While it is up, the switch is not tapped again.
    /// - Returns: whether the value changed or `shows` appeared. A switch
    ///   that is not there at all fails the test.
    @discardableResult
    func flip(
        _ toggle: XCUIElement,
        shows: XCUIElement? = nil,
        retries: Int = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard toggle.waitForExistence(timeout: 5) else {
            XCTFail("\(toggle) is missing", file: file, line: line)
            return false
        }
        let before = toggle.value as? String
        let inner = toggle.switches.firstMatch
        if inner.exists, inner.isHittable {
            inner.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        // A format predicate, not a block: XCTest re-reads the element for a
        // format predicate, while a block can see the value from before the tap
        // and tap a second time, turning the switch back.
        let changed = NSPredicate(format: "exists == false OR value != %@", before ?? "")
        for attempt in 0...retries {
            if let shows, shows.waitForExistence(timeout: 2) { return true }
            if XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: changed, object: toggle)], timeout: 3) == .completed {
                return true
            }
            guard attempt < retries, toggle.exists, !(shows?.exists ?? false) else { break }
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        if let shows { return shows.exists }
        return toggle.exists && toggle.value as? String != before
    }
}
