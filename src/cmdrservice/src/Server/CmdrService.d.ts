import { Promise } from '@quenty/promise';
import { ServiceBag } from '@quenty/servicebag';
import { Cmdr, CommandContext, CommandDefinition } from '../Shared/CmdrTypes';

interface GroupCommandPermission {
  rankInGroupRange: NumberRange;
  commandGroups: string[];
}

type GroupCommandPermissions = GroupCommandPermission[];

export interface CmdrService {
  readonly ServiceName: 'CmdrService';
  Init(serviceBag: ServiceBag): void;
  PromiseCmdr(): Promise<Cmdr>;
  RegisterCommand(
    commandData: CommandDefinition,
    execute: (context: CommandContext, ...args: any[]) => string | undefined
  ): void;
  RegisterDefaultCommands(
    ...args: Parameters<typeof Cmdr.RegisterDefaultCommands>
  ): void;
  SetGroupCommandPermissions(
    groupId: number,
    permissions: GroupCommandPermissions
  ): void;
  Destroy(): void;
}
