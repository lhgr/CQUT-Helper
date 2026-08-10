import 'package:flutter/material.dart';

@immutable
class AppSelectOption<T> {
  final T value;
  final String label;
  final String? description;
  final IconData? icon;

  const AppSelectOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
  });
}

class AppSelectField<T> extends StatelessWidget {
  final T value;
  final String labelText;
  final String? sheetTitle;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T>? onChanged;

  const AppSelectField({
    super.key,
    required this.value,
    required this.labelText,
    required this.options,
    required this.onChanged,
    this.sheetTitle,
  });

  AppSelectOption<T>? get _selectedOption {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return null;
  }

  Future<void> _openOptions(BuildContext context) async {
    if (onChanged == null) return;
    final result = await showModalBottomSheet<_AppSelectResult<T>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => _AppSelectSheet<T>(
        title: sheetTitle ?? labelText,
        value: value,
        options: options,
      ),
    );
    if (result != null && context.mounted) onChanged?.call(result.value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final selected = _selectedOption;
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      enabled: enabled,
      label: labelText,
      value: selected?.label ?? '',
      child: InkWell(
        onTap: enabled ? () => _openOptions(context) : null,
        borderRadius: BorderRadius.circular(16),
        child: InputDecorator(
          isEmpty: selected == null,
          decoration: InputDecoration(
            labelText: labelText,
            enabled: enabled,
            suffixIcon: Icon(
              Icons.expand_more_rounded,
              color: enabled
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onSurface.withAlpha(95),
            ),
          ),
          child: Text(
            selected?.label ?? '请选择',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withAlpha(95),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppSelectSheet<T> extends StatelessWidget {
  final String title;
  final T value;
  final List<AppSelectOption<T>> options;

  const _AppSelectSheet({
    required this.title,
    required this.value,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final selected = option.value == value;
                  return Material(
                    color: selected
                        ? colorScheme.secondaryContainer
                        : colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      minTileHeight: option.description == null ? 58 : 68,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 3,
                      ),
                      leading: option.icon == null
                          ? Icon(
                              selected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: selected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            )
                          : Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: selected
                                    ? colorScheme.primary.withAlpha(28)
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                option.icon,
                                size: 21,
                                color: selected
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                      title: Text(
                        option.label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onSurface,
                        ),
                      ),
                      subtitle: option.description == null
                          ? null
                          : Text(option.description!),
                      trailing: selected
                          ? Icon(
                              Icons.check_rounded,
                              color: colorScheme.primary,
                            )
                          : null,
                      selected: selected,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(_AppSelectResult(option.value)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppSelectResult<T> {
  final T value;

  const _AppSelectResult(this.value);
}
