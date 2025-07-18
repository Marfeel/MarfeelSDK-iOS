//
//  TikOperationFactory.swift
//  CompassSDK
//
//  Created by  on 09/02/2021.
//

import Foundation

protocol TikOperationFactory {
    func buildOperation(
        dataBuilder: @escaping DataBuilder,
        dispatchDate: Date,
        path: String?,
        contentType: ContentType?
    ) -> Operation
}

class TickOperationProvider: TikOperationFactory {
    private let sharedTikUseCase: SendTikCuseCase

    init(tikUseCase: SendTikCuseCase = SendTik()) {
        self.sharedTikUseCase = tikUseCase
    }
    
    func buildOperation(dataBuilder: @escaping DataBuilder, dispatchDate: Date, path: String?, contentType: ContentType?) -> Operation {
        TikOperation(dataBuilder: dataBuilder, dispatchDate: dispatchDate, tikUseCase: sharedTikUseCase, path: path, contentType: contentType)
    }
}
