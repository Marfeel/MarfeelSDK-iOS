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
    func buildOperation(dataBuilder: @escaping DataBuilder, dispatchDate: Date, path: String?, contentType: ContentType?) -> Operation {
        TikOperation(dataBuilder: dataBuilder, dispatchDate: dispatchDate, tikUseCase: SendTik(), path: path, contentType: contentType)
    }
}
