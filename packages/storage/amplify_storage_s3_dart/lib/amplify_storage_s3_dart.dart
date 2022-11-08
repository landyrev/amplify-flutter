// Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// Amplify Storage S3 for Dart
library amplify_storage_s3_dart;

export 'src/amplify_storage_s3_dart_impl.dart';

export 'src/error/invalid_bytes_range_error.dart';
export 'src/exception/s3_storage_exception.dart';

export 'src/model/s3_models.dart';

export 'src/prefix_resolver/pass_through_prefix_resolver.dart';
export 'src/prefix_resolver/s3_prefix_resolver.dart';