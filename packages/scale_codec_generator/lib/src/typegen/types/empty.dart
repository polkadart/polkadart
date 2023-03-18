part of generators;

class EmptyDescriptor extends TypeDescriptor {
  final int _id;
  EmptyDescriptor(int id) : _id = id;

  @override
  int id() => _id;

  @override
  TypeReference primitive(BasePath from) {
    return refs.dynamic.type as TypeReference;
  }

  @override
  TypeReference codec(BasePath from) {
    return refs.emptyCodec.type as TypeReference;
  }

  @override
  Expression valueFrom(BasePath from, Input input, {bool constant = false}) {
    return literalNull;
  }

  @override
  TypeReference jsonType(BasePath from,
      [Set<TypeDescriptor> visited = const {}]) {
    return refs.dynamic.type as TypeReference;
  }

  @override
  Expression instanceToJson(BasePath from, Expression obj) {
    return literalNull;
  }
}
