//
//  Publishers.ReplaceError.swift
//  OpenCombine
//
//  Created by Bogdan Vlad on 8/29/19.
//

import COpenCombineHelpers

extension Publisher {
    /// Replaces any errors in the stream with the provided element.
    ///
    /// If the upstream publisher fails with an error, this publisher emits the provided
    /// element, then finishes normally.
    /// - Parameter output: An element to emit when the upstream publisher fails.
    /// - Returns: A publisher that replaces an error from the upstream publisher with
    ///            the provided output element.
    public func replaceError(with output: Output) -> Publishers.ReplaceError<Self> {
        return .init(upstream: self, output: output)
    }
}

extension Publishers {
    /// A publisher that replaces any errors in the stream with a provided element.
    public struct ReplaceError<Upstream: Publisher>: Publisher {

        /// The kind of values published by this publisher.
        public typealias Output = Upstream.Output

        /// The kind of errors this publisher might publish.
        ///
        /// Use `Never` if this `Publisher` does not publish errors.
        public typealias Failure = Never

        /// The element with which to replace errors from the upstream publisher.
        public let output: Upstream.Output

        /// The publisher from which this publisher receives elements.
        public let upstream: Upstream

        public init(upstream: Upstream,
                    output: Output) {
            self.upstream = upstream
            self.output = output
        }

        /// This function is called to attach the specified `Subscriber`
        /// to this `Publisher` by `subscribe(_:)`
        ///
        /// - SeeAlso: `subscribe(_:)`
        /// - Parameters:
        ///     - subscriber: The subscriber to attach to this `Publisher`.
        ///                   once attached it can begin to receive values.
        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where Upstream.Output == Downstream.Input, Downstream.Failure == Failure
        {
            let inner = Inner(downstream: subscriber, output: output)
            upstream.subscribe(inner)
            subscriber.receive(subscription: inner)
        }
    }
}

extension Publishers.ReplaceError: Equatable
    where Upstream: Equatable, Upstream.Output: Equatable
{}

extension Publishers.ReplaceError {

    private final class Inner<Downstream: Subscriber>
        : Subscriber,
          Subscription,
          CustomStringConvertible,
          CustomReflectable,
          CustomPlaygroundDisplayConvertible
        where Upstream.Output == Downstream.Input
    {
        // NOTE: this class has been audited for thread safety.

        typealias Input = Upstream.Output
        typealias Failure = Upstream.Failure

        private let output: Upstream.Output
        private let downstream: Downstream
        private var status = SubscriptionStatus.awaitingSubscription
        private var terminated = false
        private var pendingDemand = Subscribers.Demand.none
        private var lock = UnfairLock.allocate()

        fileprivate init(downstream: Downstream, output: Upstream.Output) {
            self.downstream = downstream
            self.output = output
        }

        deinit {
            lock.deallocate()
        }

        func receive(subscription: Subscription) {
            lock.lock()
            guard case .awaitingSubscription = status else {
                lock.unlock()
                subscription.cancel()
                return
            }
            status = .subscribed(subscription)
            let pendingDemand = self.pendingDemand
            lock.unlock()
            if pendingDemand > 0 {
                subscription.request(pendingDemand)
            }
        }

        func receive(_ input: Upstream.Output) -> Subscribers.Demand {
            lock.lock()
            guard case .subscribed = status else {
                lock.unlock()
                return .none
            }
            pendingDemand -= 1
            lock.unlock()
            let demand = downstream.receive(input)
            guard demand > 0 else {
                return .none
            }
            lock.lock()
            pendingDemand += demand
            lock.unlock()
            return demand
        }

        func receive(completion: Subscribers.Completion<Upstream.Failure>) {
            switch completion {
            case .finished:
                downstream.receive(completion: .finished)
            case .failure:
                lock.lock()
                // If there was no demand from downstream,
                // ReplaceError does not forward the value that
                // replaces the error until it is requested.
                guard pendingDemand > 0 else {
                    terminated = true
                    lock.unlock()
                    return
                }
                lock.unlock()
                _ = downstream.receive(output)
                downstream.receive(completion: .finished)
            }
        }

        func request(_ demand: Subscribers.Demand) {
            demand.assertNonZero()
            lock.lock()
            if terminated {
                status = .terminal
                lock.unlock()
                _ = downstream.receive(output)
                downstream.receive(completion: .finished)
                return
            }
            pendingDemand += demand
            guard case let .subscribed(subscription) = status else {
                lock.unlock()
                return
            }
            lock.unlock()
            subscription.request(demand)
        }

        func cancel() {
            lock.lock()
            guard case let .subscribed(subscription) = status else {
                lock.unlock()
                return
            }
            status = .terminal
            lock.unlock()
            subscription.cancel()
        }

        var description: String { return "ReplaceError" }

        var customMirror: Mirror {
            return Mirror(self, children: EmptyCollection())
        }

        var playgroundDescription: Any { return description }
    }
}
