export interface GroupRankConfigInput {
  groupId: number;
  minAdminRequiredRank: number;
  minCreatorRequiredRank: number;
  creatorUserIds?: number[];
  adminUserIds?: number[];
  remoteFunctionName?: string;
}

export interface GroupRankConfig extends Omit<
  GroupRankConfigInput,
  'remoteFunctionName'
> {
  type: 'GroupRankConfigType';
  remoteFunctionName: string;
}

export interface SingleUserConfigInput {
  userId: number;
  remoteFunctionName?: string;
}

export interface SingleUserConfig extends Omit<
  SingleUserConfigInput,
  'remoteFunctionName'
> {
  type: 'SingleUserConfigType';
  remoteFunctionName: string;
}

export type PermissionProviderConfig = GroupRankConfig | SingleUserConfig;

export namespace PermissionProviderUtils {
  function createGroupRankConfig(config: GroupRankConfigInput): GroupRankConfig;
  function createSingleUserConfig(
    config: SingleUserConfigInput
  ): SingleUserConfig;
  function createConfigFromGame(): PermissionProviderConfig;
}
