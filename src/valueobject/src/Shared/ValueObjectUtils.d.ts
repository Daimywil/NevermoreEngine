import { Brio } from '@quenty/brio';
import { Observable } from '@quenty/rx';
import { ValueObject } from './ValueObject';
import { Signal, SignalConnection } from '@quenty/signal';

interface ValueChangedObjectLike<T> {
  Value: T;
  Changed: Signal | Signal<unknown>;
}

export namespace ValueObjectUtils {
  function syncValue<T>(
    from: ValueChangedObjectLike<T>,
    to: ValueChangedObjectLike<T>
  ): SignalConnection;
  function observeValue<T>(valueObject: ValueObject<T>): Observable<T>;
  function observeValueBrio<T>(
    valueObject: ValueObject<T>
  ): Observable<Brio<T>>;
}
