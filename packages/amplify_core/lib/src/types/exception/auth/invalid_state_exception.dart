/*
 * Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 * You may not use this file except in compliance with the License.
 * A copy of the License is located at
 *
 *  http://aws.amazon.com/apache2.0
 *
 * or in the "license" file accompanying this file. This file is distributed
 * on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 * express or implied. See the License for the specific language governing
 * permissions and limitations under the License.
 */

import 'package:amplify_core/amplify_core.dart';

/// {@template amplify_core.auth.invalid_state_exception}
/// Exception thrown when the requested operation is not valid in the current
/// Amplity Auth state.
/// {@endtemplate}
class InvalidStateException extends AuthException {
  /// {@macro amplify_core.auth.invalid_state_exception}
  const InvalidStateException(
    String message, {
    String? recoverySuggestion,
    String? underlyingException,
  }) : super(
          message,
          recoverySuggestion: recoverySuggestion,
          underlyingException: underlyingException,
        );

  /// {@macro amplify_core.auth.exception_downcasting}
  InvalidStateException._private(AuthException exception)
      : super(
          exception.message,
          recoverySuggestion: exception.recoverySuggestion,
          underlyingException: exception.underlyingException,
        );

  /// {@macro amplify_core.auth.exception_from_map}
  static InvalidStateException fromMap(
    Map<String, String> serializedException,
  ) {
    return InvalidStateException._private(
      AuthException.fromMap(serializedException),
    );
  }
}