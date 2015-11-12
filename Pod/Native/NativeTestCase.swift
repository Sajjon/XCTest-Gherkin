//
//  Example.swift
//  whats-new
//
//  Created by Sam Dean on 04/11/2015.
//  Copyright © 2015 net-a-porter. All rights reserved.
//

import Foundation
import ObjectiveC

import XCTest

public class NativeTestCase : XCTestCase {
    
    // Set some default values for this subclass; these should be overridden by subclasses
    public var path:NSURL? { get { return nil } }
    public var tags:[String] { get { return [] } }
   
    /**
     This method will dynamically create tests from the files in the folder specified by setting the path property on this instance.
    */
    func testRunNativeTests() {
        // If this hasn't been subclassed, just return
        guard self.dynamicType != NativeTestCase.self else { return }
        
        // Sanity
        guard let path = self.path else {
            XCTAssertNotNil(self.path, "You must set the path for this test to run")
            return
        }
        
        // Get the files from that folder
        guard let files = NSFileManager.defaultManager().enumeratorAtURL(path, includingPropertiesForKeys: nil, options: [], errorHandler: nil) else {
            XCTFail("Could not open the path '\(path)'")
            return
        }
        
        files.forEach { parseAndRunFeature($0 as! NSURL) }
    }
    
    private func parseAndRunFeature(url: NSURL) {
        print("Running tests from \(url.lastPathComponent!)")
        
        // Parse the lines into a feature
        let feature = NativeFeature(contentsOfURL: url)
        XCTAssertNotNil(feature, "Could not parse \(url.lastPathComponent) into a feature")
        
        // Perform the feature
        performFeature(feature!)
    }
    
    func performFeature(feature: NativeFeature) {
        // Create a test case to contain our tests
        let testClassName = "\(self.dynamicType)\(feature.featureDescription.camelCaseify)Tests"
        let testCaseClassOptional:AnyClass? = objc_allocateClassPair(XCTestCase.self, testClassName, 0)
        guard let testCaseClass = testCaseClassOptional else { XCTFail("Could not create test case class"); return }
        
        // Return the correct number of tests
        let countBlock : @convention(block) (AnyObject) -> UInt = { _ in
            return UInt(feature.scenarios.count)
        }
        let imp = imp_implementationWithBlock(unsafeBitCast(countBlock, AnyObject.self))
        let sel = sel_registerName(strdup("testCaseCount"))
        var success = class_addMethod(testCaseClass, sel, imp, strdup("I@:"))
        XCTAssertTrue(success)
        
        // Return a name
        let nameBlock : @convention(block) (AnyObject) -> String = { _ in
            return feature.featureDescription.camelCaseify
        }
        let nameImp = imp_implementationWithBlock(unsafeBitCast(nameBlock, AnyObject.self))
        let nameSel = sel_registerName(strdup("name"))
        success = class_addMethod(testCaseClass, nameSel, nameImp, strdup("@@:"))
        XCTAssertTrue(success)
        
        // Return a test run class - make it the same as the current run
        let runBlock : @convention(block) (AnyObject) -> AnyObject! = { _ in
            return self.testRun!.dynamicType
        }
        let runImp = imp_implementationWithBlock(unsafeBitCast(runBlock, AnyObject.self))
        let runSel = sel_registerName(strdup("testRunClass"))
        success = class_addMethod(testCaseClass, runSel, runImp, strdup("#@:"))
        XCTAssertTrue(success)
        
        // For each scenario, make an invocation that runs through the steps
        let typeString = strdup("v@:")
        for scenario in feature.scenarios {
            // If this scenario doesn't have the correct tags, don't run it
            if !isScenario(scenario, validWithTags:self.tags) { continue }
            
            print(scenario.description)
            
            // Create the block representing the test to be run
            let block : @convention(block) (XCTestCase)->() = { innerSelf in
                scenario.stepDescriptions.forEach { innerSelf.performStep($0) }
            }
            
            // Create the Method and selector
            let imp = imp_implementationWithBlock(unsafeBitCast(block, AnyObject.self))
            let sel = sel_registerName(scenario.selectorCString)
            
            // Add this selector to ourselves
            let success = class_addMethod(testCaseClass, sel, imp, typeString)
            XCTAssertTrue(success, "Failed to add class method \(sel)")
        }
        
        // The test class is constructed, register it
        objc_registerClassPair(testCaseClass)
        
        // Add the test to our test suite
        testCaseClass.testInvocations().sort { (a,b) in NSStringFromSelector(a.selector) > NSStringFromSelector(b.selector) }.forEach { invocation in
            let testCase = (testCaseClass as! XCTestCase.Type).init(invocation: invocation)
            testCase.runTest()
        }
        
    }
    
    private func isScenario(scenario: NativeScenario, validWithTags tags: [String]) -> Bool {
        // If there aren't any tags, that means accept anything
        guard tags.count > 0 else { return true }
        
        // If we contain _any_ of the tags, this scenario is OK
        for tag in tags {
            if scenario.tags.contains(tag) {
                return true
            }
        }

        // There were tag and we didn't have any
        return false
    }
}
