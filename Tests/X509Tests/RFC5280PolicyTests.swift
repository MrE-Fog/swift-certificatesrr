//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftCertificates open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftCertificates project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftCertificates project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import XCTest
import SwiftASN1
@testable import X509
import Crypto

final class RFC5280PolicyTests: XCTestCase {
    enum PolicyFactory {
        case rfc5280
        case expiry
        case basicConstraints

        func create(_ validationTime: Date) -> VerifierPolicy {
            switch self {
            case .rfc5280:
                return RFC5280Policy(validationTime: validationTime)
            case .expiry:
                return ExpiryPolicy(validationTime: validationTime)
            case .basicConstraints:
                return BasicConstraintsPolicy()
            }
        }
    }

    func testValidCertsAreAccepted() async throws {
        let roots = CertificateStore([TestPKI.unconstrainedCA])
        let leaf = TestPKI.issueLeaf(issuer: .unconstrainedIntermediate)

        var verifier = Verifier(rootCertificates: roots, policy: PolicySet(policies: [RFC5280Policy(validationTime: Date())]))
        let result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([TestPKI.unconstrainedIntermediate]))

        guard case .validCertificate(let chain) = result else {
            XCTFail("Failed to validate: \(result)")
            return
        }

        XCTAssertEqual(chain, [leaf, TestPKI.unconstrainedIntermediate, TestPKI.unconstrainedCA])
    }

    private func _expiredLeafIsRejected(_ policyFactory: PolicyFactory) async throws {
        let roots = CertificateStore([TestPKI.unconstrainedCA])
        let leaf = TestPKI.issueLeaf(
            notValidBefore: TestPKI.startDate + 1.0,
            notValidAfter: TestPKI.startDate + 2.0,  // One second validity window
            issuer: .unconstrainedIntermediate
        )

        var verifier = Verifier(
            rootCertificates: roots, policy: PolicySet(policies: [policyFactory.create(TestPKI.startDate + 3.0)])
        )
        let result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([TestPKI.unconstrainedIntermediate]))

        guard case .couldNotValidate(let policyFailures) = result else {
            XCTFail("Failed to validate: \(result)")
            return
        }

        XCTAssertEqual(policyFailures.count, 1)
    }

    func testExpiredLeafIsRejected() async throws {
        try await self._expiredLeafIsRejected(.rfc5280)
    }

    func testExpiredLeafIsRejectedBasePolicy() async throws {
        try await self._expiredLeafIsRejected(.expiry)
    }

    func _expiredIntermediateIsRejected(_ policyFactory: PolicyFactory) async throws {
        let roots = CertificateStore([TestPKI.unconstrainedCA])
        let leaf = TestPKI.issueLeaf(
            notValidBefore: TestPKI.startDate,
            notValidAfter: TestPKI.unconstrainedIntermediate.notValidAfter + 2.0,  // Later than the intermediate.
            issuer: .unconstrainedIntermediate
        )

        var verifier = Verifier(
            rootCertificates: roots,
            policy: PolicySet(policies: [policyFactory.create(TestPKI.unconstrainedIntermediate.notValidAfter + 1.0)])
        )
        let result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([TestPKI.unconstrainedIntermediate]))

        guard case .couldNotValidate(let policyFailures) = result else {
            XCTFail("Failed to validate: \(result)")
            return
        }

        XCTAssertEqual(policyFailures.count, 1)
    }

    func testExpiredIntermediateIsRejected() async throws {
        try await self._expiredIntermediateIsRejected(.rfc5280)
    }

    func testExpiredIntermediateIsRejectedBasePolicy() async throws {
        try await self._expiredIntermediateIsRejected(.expiry)
    }

    func _expiredRootIsRejected(_ policyFactory: PolicyFactory) async throws {
        let roots = CertificateStore([TestPKI.unconstrainedCA])
        let leaf = TestPKI.issueLeaf(
            notValidBefore: TestPKI.startDate,
            notValidAfter: TestPKI.unconstrainedCA.notValidAfter + 2.0,  // Later than the root.
            issuer: .unconstrainedRoot  // Issue off the root directly to avoid the intermediate getting involved.
        )

        var verifier = Verifier(
            rootCertificates: roots,
            policy: PolicySet(policies: [policyFactory.create(TestPKI.unconstrainedCA.notValidAfter + 1.0)])
        )
        let result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([TestPKI.unconstrainedIntermediate]))

        guard case .couldNotValidate(let policyFailures) = result else {
            XCTFail("Failed to validate: \(result)")
            return
        }

        XCTAssertEqual(policyFailures.count, 1)
    }

    func testExpiredRootIsRejected() async throws {
        try await self._expiredRootIsRejected(.rfc5280)
    }

    func testExpiredRootIsRejectedBasePolicy() async throws {
        try await self._expiredRootIsRejected(.expiry)
    }

    func _notYetValidLeafIsRejected(_ policyFactory: PolicyFactory) async throws {
        let roots = CertificateStore([TestPKI.unconstrainedCA])
        let leaf = TestPKI.issueLeaf(
            notValidBefore: TestPKI.startDate + 2.0,
            notValidAfter: TestPKI.startDate + 3.0,  // One second validity window
            issuer: .unconstrainedIntermediate
        )

        var verifier = Verifier(
            rootCertificates: roots, policy: PolicySet(policies: [policyFactory.create(TestPKI.startDate + 1.0)])
        )
        let result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([TestPKI.unconstrainedIntermediate]))

        guard case .couldNotValidate(let policyFailures) = result else {
            XCTFail("Failed to validate: \(result)")
            return
        }

        XCTAssertEqual(policyFailures.count, 1)
    }

    func testNotYetValidLeafIsRejected() async throws {
        try await self._notYetValidLeafIsRejected(.rfc5280)
    }

    func testNotYetValidLeafIsRejectedBasePolicy() async throws {
        try await self._notYetValidLeafIsRejected(.expiry)
    }

    func _notYetValidIntermediateIsRejected(_ policyFactory: PolicyFactory) async throws {
        let roots = CertificateStore([TestPKI.unconstrainedCA])
        let leaf = TestPKI.issueLeaf(
            notValidBefore: TestPKI.unconstrainedIntermediate.notValidBefore - 2.0,  // Earlier than the intermediate
            notValidAfter: TestPKI.unconstrainedIntermediate.notValidAfter,
            issuer: .unconstrainedIntermediate
        )

        var verifier = Verifier(
            rootCertificates: roots,
            policy: PolicySet(policies: [policyFactory.create(TestPKI.unconstrainedIntermediate.notValidBefore - 1.0)])
        )
        let result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([TestPKI.unconstrainedIntermediate]))

        guard case .couldNotValidate(let policyFailures) = result else {
            XCTFail("Failed to validate: \(result)")
            return
        }

        XCTAssertEqual(policyFailures.count, 1)
    }

    func testNotYetValidIntermediateIsRejected() async throws {
        try await self._notYetValidIntermediateIsRejected(.rfc5280)
    }

    func testNotYetValidIntermediateIsRejectedBasePolicy() async throws {
        try await self._notYetValidIntermediateIsRejected(.expiry)
    }

    func _notYetValidRootIsRejected(_ policyFactory: PolicyFactory) async throws {
        let roots = CertificateStore([TestPKI.unconstrainedCA])
        let leaf = TestPKI.issueLeaf(
            notValidBefore: TestPKI.unconstrainedCA.notValidBefore - 2.0,  // Earlier than the root
            notValidAfter: TestPKI.startDate,
            issuer: .unconstrainedRoot  // Issue off the root directly to avoid the intermediate getting involved.
        )

        var verifier = Verifier(
            rootCertificates: roots,
            policy: PolicySet(policies: [policyFactory.create(TestPKI.unconstrainedCA.notValidBefore - 1.0)])
        )
        let result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([TestPKI.unconstrainedIntermediate]))

        guard case .couldNotValidate(let policyFailures) = result else {
            XCTFail("Failed to validate: \(result)")
            return
        }

        XCTAssertEqual(policyFailures.count, 1)
    }

    func testNotYetValidRootIsRejected() async throws {
        try await self._notYetValidRootIsRejected(.rfc5280)
    }

    func testNotYetValidRootIsRejectedBasePolicy() async throws {
        try await self._notYetValidRootIsRejected(.expiry)
    }

    func _malformedExpiryIsRejected(_ policyFactory: PolicyFactory) async throws {
        let roots = CertificateStore([TestPKI.unconstrainedCA])
        let leaf = TestPKI.issueLeaf(
            notValidBefore: TestPKI.startDate + 3.0,
            notValidAfter: TestPKI.startDate + 2.0,  // invalid order
            issuer: .unconstrainedIntermediate
        )

        var verifier = Verifier(
            rootCertificates: roots, policy: PolicySet(policies: [policyFactory.create(TestPKI.startDate + 2.5)])
        )
        let result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([TestPKI.unconstrainedIntermediate]))

        guard case .couldNotValidate(let policyFailures) = result else {
            XCTFail("Failed to validate: \(result)")
            return
        }

        XCTAssertEqual(policyFailures.count, 1)
    }

    func testMalformedExpiryIsRejected() async throws {
        try await self._malformedExpiryIsRejected(.rfc5280)
    }

    func testMalformedExpiryIsRejectedBasePolicy() async throws {
        try await self._malformedExpiryIsRejected(.expiry)
    }

    // This is a BasicConstraints extension that is invalid gibberish
    private static let brokenBasicConstraints = Certificate.Extension(
        oid: .X509ExtensionID.basicConstraints, critical: true, value: [1, 2, 3, 4, 5, 6, 7, 8, 9]
    )

    func _selfSignedCertsMustBeMarkedAsCA(_ policyFactory: PolicyFactory) async throws {
        let certsAndValidity = [
            (TestPKI.issueSelfSignedCert(basicConstraints: .isCertificateAuthority(maxPathLength: nil)), true),
            (TestPKI.issueSelfSignedCert(basicConstraints: .isCertificateAuthority(maxPathLength: 0)), true),
            (TestPKI.issueSelfSignedCert(basicConstraints: .notCertificateAuthority), false),
            (TestPKI.issueSelfSignedCert(customExtensions: Certificate.Extensions([Self.brokenBasicConstraints])), false)
        ]

        for (cert, isValid) in certsAndValidity {
            var verifier = Verifier(
                rootCertificates: CertificateStore([cert]),
                policy: PolicySet(policies: [policyFactory.create(TestPKI.startDate + 2.5)])
            )
            let result = await verifier.validate(leafCertificate: cert, intermediates: CertificateStore([]))

            switch (result, isValid) {
            case (.validCertificate, true),
                (.couldNotValidate, false):
                ()
            case (_, true):
                XCTFail("Failed to validate: \(result) \(cert)")
            case (_, false):
                XCTFail("Incorrectly validated: \(result) \(cert)")
            }
        }
    }

    func testSelfSignedCertsMustBeMarkedAsCA() async throws {
        try await self._selfSignedCertsMustBeMarkedAsCA(.rfc5280)
    }

    func testSelfSignedCertsMustBeMarkedAsCABasePolicy() async throws {
        try await self._selfSignedCertsMustBeMarkedAsCA(.basicConstraints)
    }

    func _intermediateCAMustBeMarkedCAInBasicConstraints(_ policyFactory: PolicyFactory) async throws {
        let invalidIntermediateCAs = [
            // Explicitly not being a CA is bad
            TestPKI.issueIntermediate(
                name: TestPKI.unconstrainedIntermediateName,
                key: .init(TestPKI.unconstrainedIntermediateKey.publicKey),
                extensions: try! Certificate.Extensions {
                    Critical(
                        BasicConstraints.notCertificateAuthority
                    )
                },
                issuer: .unconstrainedRoot
            ),

            // Not having BasicConstraints at all is also bad.
            TestPKI.issueIntermediate(
                name: TestPKI.unconstrainedIntermediateName,
                key: .init(TestPKI.unconstrainedIntermediateKey.publicKey),
                extensions: Certificate.Extensions([]),
                issuer: .unconstrainedRoot
            ),

            // As is having broken BasicConstraints
            TestPKI.issueIntermediate(
                name: TestPKI.unconstrainedIntermediateName,
                key: .init(TestPKI.unconstrainedIntermediateKey.publicKey),
                extensions: Certificate.Extensions([Self.brokenBasicConstraints]),
                issuer: .unconstrainedRoot
            )
        ]

        let leaf = TestPKI.issueLeaf(issuer: .unconstrainedIntermediate)

        for badIntermediate in invalidIntermediateCAs {
            var verifier = Verifier(
                rootCertificates: CertificateStore([TestPKI.unconstrainedCA]),
                policy: PolicySet(policies: [policyFactory.create(TestPKI.startDate + 2.5)])
            )
            var result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([badIntermediate]))

            guard case .couldNotValidate = result else {
                XCTFail("Incorrectly validated with \(badIntermediate) in chain")
                return
            }

            // Adding the better CA in works better, _and_ we don't use the bad intermediate!
            verifier = Verifier(
                rootCertificates: CertificateStore([TestPKI.unconstrainedCA]),
                policy: PolicySet(policies: [policyFactory.create(TestPKI.startDate + 2.5)])
            )
            result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([badIntermediate, TestPKI.unconstrainedIntermediate]))

            guard case .validCertificate(let chain) = result else {
                XCTFail("Unable to validate with both bad and good intermediate in chain")
                return
            }

            XCTAssertEqual(chain, [leaf, TestPKI.unconstrainedIntermediate, TestPKI.unconstrainedCA])
        }
    }

    func testIntermediateCAMustBeMarkedAsCAInBasicConstraints() async throws {
        try await self._intermediateCAMustBeMarkedCAInBasicConstraints(.rfc5280)
    }

    func testIntermediateCAMustBeMarkedAsCAInBasicConstraintsBasePolicy() async throws {
        try await self._intermediateCAMustBeMarkedCAInBasicConstraints(.basicConstraints)
    }

    func _rootCAMustBeMarkedCAInBasicConstraints(_ policyFactory: PolicyFactory) async throws {
        let invalidRootCAs = [
            // Explicitly not being a CA is bad
            TestPKI.issueCA(extensions: try! Certificate.Extensions {
                Critical(
                    BasicConstraints.notCertificateAuthority
                )
            }),

            // Not having BasicConstraints at all is also bad.
            TestPKI.issueCA(extensions: Certificate.Extensions([])),

            // As is having broken BasicConstraints
            TestPKI.issueCA(extensions: Certificate.Extensions([Self.brokenBasicConstraints]))
        ]

        let leaf = TestPKI.issueLeaf(issuer: .unconstrainedIntermediate)

        for badRoot in invalidRootCAs {
            var verifier = Verifier(
                rootCertificates: CertificateStore([badRoot]),
                policy: PolicySet(policies: [policyFactory.create(TestPKI.startDate + 2.5)])
            )
            var result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([TestPKI.unconstrainedIntermediate]))

            guard case .couldNotValidate = result else {
                XCTFail("Incorrectly validated with \(badRoot) in chain")
                return
            }

            // Adding the better CA in works better, _and_ we don't use the bad root!
            verifier = Verifier(
                rootCertificates: CertificateStore([badRoot, TestPKI.unconstrainedCA]),
                policy: PolicySet(policies: [policyFactory.create(TestPKI.startDate + 2.5)])
            )
            result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([TestPKI.unconstrainedIntermediate]))

            guard case .validCertificate(let chain) = result else {
                XCTFail("Unable to validate with both bad and good root in chain")
                return
            }

            XCTAssertEqual(chain, [leaf, TestPKI.unconstrainedIntermediate, TestPKI.unconstrainedCA])
        }
    }

    func testRootCAMustBeMarkedAsCAInBasicConstraints() async throws {
        try await self._rootCAMustBeMarkedCAInBasicConstraints(.rfc5280)
    }

    func testRootCAMustBeMarkedAsCAInBasicConstraintsBasePolicy() async throws {
        try await self._rootCAMustBeMarkedCAInBasicConstraints(.basicConstraints)
    }

    func _pathLengthConstraintsFromIntermediatesAreApplied(_ policyFactory: PolicyFactory) async throws {
        // This test requires that we use a second-level intermediate, to police the first-level
        // intermediate's path length constraint. This second level intermediate has a valid path length
        // constraint.
        let secondLevelIntermediate = TestPKI.issueIntermediate(
            name: TestPKI.secondLevelIntermediateName,
            key: .init(TestPKI.secondLevelIntermediateKey.publicKey),
            extensions: try! Certificate.Extensions {
                Critical(
                    BasicConstraints.isCertificateAuthority(maxPathLength: 0)
                )
            },
            issuer: .unconstrainedIntermediate
        )

        let leaf = TestPKI.issueLeaf(issuer: .secondLevelIntermediate)

        var verifier = Verifier(
            rootCertificates: CertificateStore([TestPKI.unconstrainedCA]),
            policy: PolicySet(policies: [policyFactory.create(TestPKI.startDate + 2.5)])
        )
        var result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([secondLevelIntermediate, TestPKI.unconstrainedIntermediate]))

        guard case .couldNotValidate = result else {
            XCTFail("Incorrectly validated with \(secondLevelIntermediate) in chain")
            return
        }

        // Creating a new first-level intermediate with a better path length constraint works!
        let newFirstLevelIntermediate = TestPKI.issueIntermediate(
            name: TestPKI.unconstrainedIntermediateName,
            key: .init(TestPKI.unconstrainedIntermediateKey.publicKey),
            extensions: try! Certificate.Extensions {
                Critical(
                    BasicConstraints.isCertificateAuthority(maxPathLength: 1)
                )
            },
            issuer: .unconstrainedRoot
        )

        verifier = Verifier(
            rootCertificates: CertificateStore([TestPKI.unconstrainedCA]),
            policy: PolicySet(policies: [policyFactory.create(TestPKI.startDate + 2.5)])
        )
        result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([secondLevelIntermediate, newFirstLevelIntermediate, TestPKI.unconstrainedIntermediate]))

        guard case .validCertificate(let chain) = result else {
            XCTFail("Unable to validate with both bad and good intermediate in chain")
            return
        }

        XCTAssertEqual(chain, [leaf, secondLevelIntermediate, newFirstLevelIntermediate, TestPKI.unconstrainedCA])
    }

    func testPathLengthConstraintsFromIntermediatesAreApplied() async throws {
        try await self._pathLengthConstraintsFromIntermediatesAreApplied(.rfc5280)
    }

    func testPathLengthConstraintsFromIntermediatesAreAppliedBasePolicy() async throws {
        try await self._pathLengthConstraintsFromIntermediatesAreApplied(.basicConstraints)
    }

    func _pathLengthConstraintsOnRootsAreApplied(_ policyFactory: PolicyFactory) async throws {
        // This test requires that we use a second-level intermediate, to police the first-level
        // intermediate's path length constraint. This second level intermediate has a valid path length
        // constraint.
        let alternativeRoot = TestPKI.issueCA(
            extensions: try! Certificate.Extensions {
                Critical(
                    BasicConstraints.isCertificateAuthority(maxPathLength: 0)
                )
            }
        )

        let leaf = TestPKI.issueLeaf(issuer: .unconstrainedIntermediate)

        var verifier = Verifier(
            rootCertificates: CertificateStore([alternativeRoot]),
            policy: PolicySet(policies: [policyFactory.create(TestPKI.startDate + 2.5)])
        )
        var result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([TestPKI.unconstrainedIntermediate]))

        guard case .couldNotValidate = result else {
            XCTFail("Incorrectly validated with \(alternativeRoot) in chain")
            return
        }

        // Adding back the good root works!
        verifier = Verifier(
            rootCertificates: CertificateStore([alternativeRoot, TestPKI.unconstrainedCA]),
            policy: PolicySet(policies: [policyFactory.create(TestPKI.startDate + 2.5)])
        )
        result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore([TestPKI.unconstrainedIntermediate]))

        guard case .validCertificate(let chain) = result else {
            XCTFail("Unable to validate with both bad and good intermediate in chain")
            return
        }

        XCTAssertEqual(chain, [leaf, TestPKI.unconstrainedIntermediate, TestPKI.unconstrainedCA])
    }

    func testPathLengthConstraintsOnRootsAreApplied() async throws {
        try await self._pathLengthConstraintsFromIntermediatesAreApplied(.rfc5280)
    }

    func testPathLengthConstraintsOnRootsAreAppliedBasePolicy() async throws {
        try await self._pathLengthConstraintsFromIntermediatesAreApplied(.basicConstraints)
    }
}

fileprivate enum TestPKI {
    static let startDate = Date()

    static let unconstrainedCAPrivateKey = P384.Signing.PrivateKey()
    static let unconstrainedCAName = try! DistinguishedName {
        CountryName("US")
        OrganizationName("Apple")
        CommonName("Swift Certificate Test CA 1")
    }
    static let unconstrainedCA: Certificate = {
        return try! Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: .init(unconstrainedCAPrivateKey.publicKey),
            notValidBefore: startDate - .days(3650),
            notValidAfter: startDate + .days(3650),
            issuer: unconstrainedCAName,
            subject: unconstrainedCAName,
            signatureAlgorithm: .ecdsaWithSHA384,
            extensions: Certificate.Extensions {
                Critical(
                    BasicConstraints.isCertificateAuthority(maxPathLength: nil)
                )
            },
            issuerPrivateKey: .init(unconstrainedCAPrivateKey)
        )
    }()
    static func issueCA(extensions: Certificate.Extensions) -> Certificate {
        return try! Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: .init(unconstrainedCAPrivateKey.publicKey),
            notValidBefore: startDate - .days(3650),
            notValidAfter: startDate + .days(3650),
            issuer: unconstrainedCAName,
            subject: unconstrainedCAName,
            signatureAlgorithm: .ecdsaWithSHA384,
            extensions: extensions,
            issuerPrivateKey: .init(unconstrainedCAPrivateKey)
        )
    }

    static let unconstrainedIntermediateKey = P256.Signing.PrivateKey()
    static let unconstrainedIntermediateName = try! DistinguishedName {
        CountryName("US")
        OrganizationName("Apple")
        CommonName("Swift Certificate Test Intermediate 1")
    }
    static let unconstrainedIntermediate: Certificate = {
        return issueIntermediate(
            name: unconstrainedIntermediateName,
            key: .init(unconstrainedIntermediateKey.publicKey),
            extensions: try! Certificate.Extensions {
                Critical(
                    BasicConstraints.isCertificateAuthority(maxPathLength: 0)
                )
            },
            issuer: .unconstrainedRoot
        )
    }()
    static func issueIntermediate(name: DistinguishedName, key: Certificate.PublicKey, extensions: Certificate.Extensions, issuer: Issuer) -> Certificate {
        return try! Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: key,
            notValidBefore: startDate - .days(365),
            notValidAfter: startDate + .days(365),
            issuer: issuer.name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: issuer.key
        )
    }

    static let secondLevelIntermediateKey = P256.Signing.PrivateKey()
    static let secondLevelIntermediateName = try! DistinguishedName {
        CountryName("US")
        OrganizationName("Apple")
        CommonName("Swift Certificate Test Intermediate 2")
    }

    enum Issuer {
        case unconstrainedRoot
        case unconstrainedIntermediate
        case secondLevelIntermediate

        var name: DistinguishedName {
            switch self {
            case .unconstrainedRoot:
                return unconstrainedCAName
            case .unconstrainedIntermediate:
                return unconstrainedIntermediateName
            case .secondLevelIntermediate:
                return secondLevelIntermediateName
            }
        }

        var key: Certificate.PrivateKey {
            switch self {
            case .unconstrainedRoot:
                return .init(unconstrainedCAPrivateKey)
            case .unconstrainedIntermediate:
                return .init(unconstrainedIntermediateKey)
            case .secondLevelIntermediate:
                return .init(secondLevelIntermediateKey)
            }
        }
    }

    static func issueLeaf(
        commonName: String = "Leaf",
        notValidBefore: Date = Self.startDate,
        notValidAfter: Date = Self.startDate + .days(365),
        issuer: Issuer
    ) -> Certificate {
        let leafKey = P256.Signing.PrivateKey()
        let name = try! DistinguishedName {
            CountryName("US")
            OrganizationName("Apple")
            CommonName(commonName)
        }

        return try! Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: .init(leafKey.publicKey),
            notValidBefore: notValidBefore,
            notValidAfter: notValidAfter,
            issuer: issuer.name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(
                    BasicConstraints.notCertificateAuthority
                )
            },
            issuerPrivateKey: issuer.key
        )
    }

    static func issueSelfSignedCert(
        commonName: String = "Leaf",
        basicConstraints: BasicConstraints = .notCertificateAuthority,
        customExtensions: Certificate.Extensions? = nil
    ) -> Certificate {
        let selfSignedKey = P256.Signing.PrivateKey()
        let name = try! DistinguishedName {
            CountryName("US")
            OrganizationName("Apple")
            CommonName(commonName)
        }

        let extensions: Certificate.Extensions

        if let customExtensions {
            extensions = customExtensions
        } else {
            extensions = try! Certificate.Extensions {
                Critical(
                    basicConstraints
                )
            }
        }

        return try! Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: .init(selfSignedKey.publicKey),
            notValidBefore: Self.startDate,
            notValidAfter: Self.startDate + .days(365),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(selfSignedKey)
        )
    }
}