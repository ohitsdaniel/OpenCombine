//
//  JSONEncoder.swift
//  
//
//  Created by Sergej Jaskiewicz on 10.10.2019.
//

import Foundation
import OpenCombine

extension JSONEncoder: TopLevelEncoder {
  public typealias Output = Data
}

extension PropertyListEncoder: TopLevelEncoder {
  public typealias Output = Data
}

extension JSONDecoder: TopLevelDecoder {
  public typealias Input = Data
}

extension PropertyListDecoder: TopLevelDecoder {
  public typealias Input = Data
}
