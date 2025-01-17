//
//  Publishers.Drop.swift
//
//
//  Created by Sven Weidauer on 03.10.2019.
//

import COpenCombineHelpers

extension Publisher {
    /// Omits the specified number of elements before republishing subsequent elements.
    ///
    /// - Parameter count: The number of elements to omit.
    /// - Returns: A publisher that does not republish the first `count` elements.
    public func dropFirst(_ count: Int = 1) -> Publishers.Drop<Self> {
        return .init(upstream: self, count: count)
    }
}

extension Publishers {
    /// A publisher that omits a specified number of elements before republishing
    /// later elements.
    public struct Drop<Upstream: Publisher>: Publisher {

        public typealias Output = Upstream.Output

        public typealias Failure = Upstream.Failure

        /// The publisher from which this publisher receives elements.
        public let upstream: Upstream

        /// The number of elements to drop.
        public let count: Int

        public init(upstream: Upstream, count: Int) {
            self.upstream = upstream
            self.count = count
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where Upstream.Failure == Downstream.Failure,
                  Upstream.Output == Downstream.Input
        {
            let inner = Inner(downstream: subscriber, count: count)
            upstream.subscribe(inner)
            subscriber.receive(subscription: inner)
        }
    }
}

extension Publishers.Drop: Equatable where Upstream: Equatable {}

extension Publishers.Drop {
    private final class Inner<Downstream: Subscriber>
        : Subscription,
          Subscriber,
          CustomStringConvertible,
          CustomReflectable,
          CustomPlaygroundDisplayConvertible
        where Upstream.Output == Downstream.Input,
              Upstream.Failure == Downstream.Failure
    {
        // NOTE: This class has been audited for thread safety.

        typealias Input = Upstream.Output

        typealias Failure = Upstream.Failure

        private let downstream: Downstream

        private let lock = UnfairLock.allocate()

        private var subscription: Subscription?

        private var pendingDemand = Subscribers.Demand.none

        private var count: Int

        fileprivate init(downstream: Downstream, count: Int) {
            self.downstream = downstream
            self.count = count
        }

        deinit {
            lock.deallocate()
        }

        func receive(subscription: Subscription) {
            lock.lock()
            guard self.subscription == nil else {
                lock.unlock()
                subscription.cancel()
                return
            }
            self.subscription = subscription
            precondition(count >= 0, "count must not be negative")
            let demandToRequestFromUpstream = pendingDemand + count
            lock.unlock()
            if demandToRequestFromUpstream > 0 {
                subscription.request(demandToRequestFromUpstream)
            }
        }

        func receive(_ input: Upstream.Output) -> Subscribers.Demand {
            // Combine doesn't lock here!
            if count > 0 {
                count -= 1
                return .none
            }
            return downstream.receive(input)
        }

        func receive(completion: Subscribers.Completion<Upstream.Failure>) {
            // Combine doesn't lock here!
            subscription = nil
            downstream.receive(completion: completion)
        }

        func request(_ demand: Subscribers.Demand) {
            demand.assertNonZero()
            lock.lock()
            guard let subscription = self.subscription else {
                self.pendingDemand += demand
                lock.unlock()
                return
            }
            lock.unlock()
            subscription.request(demand)
        }

        func cancel() {
            // Combine doesn't lock here!
            subscription?.cancel()
            subscription = nil
        }

        var description: String { return "Drop" }

        var customMirror: Mirror {
            return Mirror(self, children: EmptyCollection())
        }

        var playgroundDescription: Any { return description }
    }
}
